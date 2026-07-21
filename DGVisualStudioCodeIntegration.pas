unit DGVisualStudioCodeIntegration;

interface

procedure Register;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Variants,
  System.UITypes,
  System.Generics.Collections,
  System.Win.Registry,
  ToolsAPI,
  DCCStrs,
  CommonOptionStrs,
  Vcl.Menus,
  Vcl.Dialogs,
  Vcl.ActnList,
  Vcl.ExtCtrls,
  Vcl.Forms,
  FrmVSCodeLaunchError,
  FrmSettingsFrame,
  PluginSettings,
  OSCmdLineExecutor,
  Winapi.Windows;


// Returns true if the module was saved successfully (or it didn't need to be saved)
function SaveModule(Module: IOTAModule): boolean;
var
  i: Integer;
  editor: IOTAEditor;
begin
  for i := 0 to Module.ModuleFileCount - 1 do begin
    editor := Module.ModuleFileEditors[i];
    if not Editor.Modified then
      continue;
    Result := Module.Save(False, True);
    Exit;
  end;
  Result := True;
  Exit;
end;

function SaveAllModules: boolean;
var
  Services: IOTAModuleServices;
  I: Integer;
  Module: IOTAModule;
begin
  Services := BorlandIDEServices as IOTAModuleServices;
  for I := 0 to Services.ModuleCount - 1 do begin
    Module := Services.Modules[I];
    if not SaveModule(Module) then begin
      Result := False;
      Exit;
    end;
  end;
  result := true;
end;

function FindSourceEditor(Module: IOTAModule; const FileExtensions: array of string): IOTASourceEditor;
var
  i: Integer;
  editor: IOTAEditor;
begin
  for i := 0 to Module.ModuleFileCount - 1 do
  begin
    editor := Module.ModuleFileEditors[i];
    if not Supports(editor, IOTASourceEditor, Result) then
      continue;
    var ext := ExtractFileExt(Result.FileName).toUpper;
    for var scan in FileExtensions do
      if scan = ext then
        Exit;
  end;

  Result := nil;
end;

type
  TCurrentSourceFileInfos = record
    FileName: string;
    Line: Integer;
    Column: Integer;
  end;

function TryGetCurrentSourceFileInfos(out FileInfos: TCurrentSourceFileInfos): Boolean;
var
  EditView: IOTAEditView;
begin
  FileInfos.FileName := '';
  FileInfos.Line := -1;
  FileInfos.Column := -1;

  var Module := (BorlandIDEServices as IOTAModuleServices).CurrentModule;
  if Module = nil then
    Exit(False);

  var Editor := FindSourceEditor(Module, ['.PAS', '.DPR', '.INC', '.DPK', '.DFM', '.FMX']);
  if Editor = nil then
    Exit(False);
  if Editor.EditViewCount = 0 then
    Exit(False);

  FileInfos.FileName := Editor.FileName;
  EditView := Editor.GetEditView(0);
  if EditView <> nil then begin
    FileInfos.Line := EditView.CursorPos.Line;
    FileInfos.Column := EditView.CursorPos.Col;
  end;
  Result := True;
end;

function GetActiveProjectGroup: IOTAProjectGroup;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
begin
  Result := nil;
  ModuleServices := BorlandIDEServices as IOTAModuleServices;
  for var i := 0 to ModuleServices.ModuleCount - 1 do begin
    Module := ModuleServices.Modules[i];
    if Supports(Module, IOTAProjectGroup, Result) then
      Exit;
  end;
end;

// Converts an absolute Windows path to a file URI as expected by VSCode:
//   C:\foo\bar.json  →  file:///c%3A/foo/bar.json
function PathToFileUri(const Path: string): string;
var
  S: string;
begin
  S := StringReplace(Path, '\', '/', [rfReplaceAll]);
  if (Length(S) >= 2) and (S[2] = ':') then
    S[1] := LowerCase(S[1])[1];
  S := StringReplace(S, ':', '%3A', [rfReplaceAll]);
  Result := 'file:///' + S;
end;

// Builds the plugin's built-in default settings.
// These are used ONLY to create the shared defaults file the first time; from
// then on that versioned file is the source of truth and this is not consulted.
function BuildBuiltInWorkspaceSettings: TJSONObject;
begin
  var Settings := TJSONObject.Create;
  Result := Settings;

  var FilesExclude := TJSONObject.Create;
  for var Pattern in ['**/Debug', '**/Release',
                      '**/Win32/Debug', '**/Win32/Release',
                      '**/Win64/Debug', '**/Win64/Release',
                      '**/__recovery', '**/__history',
                      '**/.#*', '**/*.rc', '**/*.res', '**/*.RES',
                      '**/*.bak', '**/*.BAK'] do
    FilesExclude.AddPair(Pattern, TJSONBool.Create(True));
  Settings.AddPair('files.exclude', FilesExclude);

  Settings.AddPair('files.trimTrailingWhitespace', TJSONBool.Create(True));
  Settings.AddPair('files.autoGuessEncoding', TJSONBool.Create(True));
  Settings.AddPair('editor.detectIndentation', TJSONBool.Create(False));
  Settings.AddPair('editor.foldingMaximumRegions', TJSONNumber.Create(8000));

  // [objectpascal]: bracket pairs for begin/end, case/end, etc.
  var PascalSettings := TJSONObject.Create;
  var PascalBrackets := TJSONArray.Create;
  for var OpenClose in ['begin|end', 'case|end', 'repeat|until',
                        'try|end', 'while|do', 'if|then', 'for|do'] do begin
    var Parts := OpenClose.Split(['|']);
    var BracketPair := TJSONArray.Create;
    BracketPair.Add(Parts[0]);
    BracketPair.Add(Parts[1]);
    PascalBrackets.Add(BracketPair);
  end;
  PascalSettings.AddPair('editor.language.brackets', PascalBrackets);
  Settings.AddPair('[objectpascal]', PascalSettings);

  // [markdown]: preserve trailing whitespace
  var MarkdownSettings := TJSONObject.Create;
  MarkdownSettings.AddPair('files.trimTrailingWhitespace', TJSONBool.Create(False));
  MarkdownSettings.AddPair('editor.trimAutoWhitespace', TJSONBool.Create(False));
  Settings.AddPair('[markdown]', MarkdownSettings);
end;

// Copies every key of ASource that ATarget does not already define. Objects are
// merged one key at a time rather than replaced, so a user who customised one
// entry of "files.exclude" still receives the other defaults. A value the user
// already set is never overwritten.
procedure MergeMissingInto(ATarget, ASource: TJSONObject);
begin
  if (ATarget = nil) or (ASource = nil) then
    Exit;

  for var Pair in ASource do begin
    var Key := Pair.JsonString.Value;
    var Existing := ATarget.GetValue(Key);
    if Existing = nil then begin
      ATarget.AddPair(Key, Pair.JsonValue.Clone as TJSONValue);
      Continue;
    end;
    if (Existing is TJSONObject) and (Pair.JsonValue is TJSONObject) then
      MergeMissingInto(TJSONObject(Existing), TJSONObject(Pair.JsonValue));
  end;
end;

// Applies standard Delphi settings to a JSON object.
// Used both in .code-workspace (Settings is the "settings" sub-object)
// and in .vscode/settings.json (Settings is the file root).
// The shared values come from the versioned defaults file; only the
// project-specific ones are still produced here.
procedure ApplyStandardDelphiSettings(Settings: TJSONObject; ActiveProject: IOTAProject;
  ADefaults: TJSONObject);
begin
  if ADefaults <> nil then
    MergeMissingInto(Settings, ADefaults.GetValue('settings') as TJSONObject);

  // delphiLsp.settingsFile: points at THIS project's .delphilsp.json, on THIS
  // machine, so it stays generated and never enters the shared file.
  if ActiveProject <> nil then begin
    var DelphiLspFile := ChangeFileExt(ActiveProject.FileName, '.delphilsp.json');
    if TFile.Exists(DelphiLspFile) and (Settings.GetValue('delphiLsp.settingsFile') = nil) then
      Settings.AddPair('delphiLsp.settingsFile', PathToFileUri(DelphiLspFile));
  end;
end;

function BuildExtensionRecommendations: TJSONArray;
begin
  Result := TJSONArray.Create;
  for var ExtId in ['embarcaderotechnologies.delphilsp'] do
    Result.Add(ExtId);
end;

const
  PLUGIN_MANAGED_BY_FIELD = 'managedBy';
  PLUGIN_MANAGED_BY_VALUE = 'editinvscode-delphi-plugin';
  PLUGIN_SETTINGS_MENU_CAPTION = 'Edit in VS Code Settings...';

// Adds the recommendations declared in the shared defaults file that the target
// does not list yet. User-added entries are preserved.
procedure MergeExtensionRecommendations(ExtensionsObject: TJSONObject; ADefaults: TJSONObject);
var
  ExistingRecommendations: TJSONArray;
  DefaultRecommendations: TJSONArray;
  OwnsDefaults: Boolean;
  HasItem: Boolean;
begin
  DefaultRecommendations := nil;
  OwnsDefaults := False;
  if ADefaults <> nil then begin
    var SharedExtensions := ADefaults.GetValue('extensions') as TJSONObject;
    if SharedExtensions <> nil then
      DefaultRecommendations := SharedExtensions.GetValue('recommendations') as TJSONArray;
  end;
  if DefaultRecommendations = nil then begin
    DefaultRecommendations := BuildExtensionRecommendations;
    OwnsDefaults := True;
  end;

  try
    ExistingRecommendations := ExtensionsObject.GetValue('recommendations') as TJSONArray;
    if ExistingRecommendations = nil then begin
      ExtensionsObject.AddPair('recommendations', DefaultRecommendations.Clone as TJSONValue);
      Exit;
    end;

    for var DefaultItem in DefaultRecommendations do begin
      HasItem := False;
      for var ExistingItem in ExistingRecommendations do
        if SameText(ExistingItem.Value, DefaultItem.Value) then begin
          HasItem := True;
          Break;
        end;
      if not HasItem then
        ExistingRecommendations.AddElement(DefaultItem.Clone as TJSONValue);
    end;
  finally
    if OwnsDefaults then
      DefaultRecommendations.Free;
  end;
end;

procedure WriteTextIfChanged(const AFileName, AContent: string; AEncoding: TEncoding); forward;

const
  // Shared with the team and meant to be put under version control, next to the
  // .groupproj (or next to the project, in folder mode). The generated
  // .code-workspace should NOT be versioned: it holds the checkout path, the
  // project that happened to be active, and a per-developer debug configuration.
  WORKSPACE_DEFAULTS_FILE = 'vscode-workspace-defaults.json';
  WORKSPACE_DEFAULTS_VERSION = 1;

// Reads the shared defaults file, creating it from the plugin's built-in
// defaults when it is absent. The caller owns the result.
// An existing but unreadable file is never overwritten: the built-in defaults
// are used in memory and the user's file is left untouched.
function LoadOrCreateWorkspaceDefaults(const ADir: string): TJSONObject;
begin
  var FileName := IncludeTrailingPathDelimiter(ADir) + WORKSPACE_DEFAULTS_FILE;
  var AlreadyExists := TFile.Exists(FileName);
  if AlreadyExists then begin
    Result := nil;
    try
      Result := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName)) as TJSONObject;
    except
      Result := nil;
    end;
    if Result <> nil then
      Exit;
  end;

  Result := TJSONObject.Create;
  Result.AddPair('$comment', 'Shared VS Code settings for this project. Put this file under ' +
    'version control. The generated .code-workspace next to it should not be versioned: it ' +
    'contains machine-specific paths and a per-developer debug configuration.');
  Result.AddPair('version', TJSONNumber.Create(WORKSPACE_DEFAULTS_VERSION));
  Result.AddPair('settings', BuildBuiltInWorkspaceSettings);
  var Extensions := TJSONObject.Create;
  Extensions.AddPair('recommendations', BuildExtensionRecommendations);
  Result.AddPair('extensions', Extensions);

  if not AlreadyExists then
    try
      WriteTextIfChanged(FileName, Result.Format, TEncoding.UTF8);
    except
      // A read-only checkout must not break workspace generation.
    end;
end;

procedure GenerateOrUpdateVSCodeFolderSettings(const FolderPath: string; ActiveProject: IOTAProject);
var
  VscodePath, SettingsFile, ExtFile: string;
  Root, ExtRoot: TJSONObject;
begin
  VscodePath := IncludeTrailingPathDelimiter(FolderPath) + '.vscode';
  if not TDirectory.Exists(VscodePath) then
    TDirectory.CreateDirectory(VscodePath);

  SettingsFile := VscodePath + '\settings.json';
  if TFile.Exists(SettingsFile) then
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(SettingsFile)) as TJSONObject
  else
    Root := nil;
  if Root = nil then
    Root := TJSONObject.Create;
  // Same shared file as in workspace mode, here next to the project.
  var SharedDefaults := LoadOrCreateWorkspaceDefaults(FolderPath);
  try
    try
      ApplyStandardDelphiSettings(Root, ActiveProject, SharedDefaults);
      WriteTextIfChanged(SettingsFile, Root.Format, TEncoding.UTF8);
    finally
      Root.Free;
    end;

    ExtFile := VscodePath + '\extensions.json';
    if TFile.Exists(ExtFile) then
      ExtRoot := TJSONObject.ParseJSONValue(TFile.ReadAllText(ExtFile)) as TJSONObject
    else
      ExtRoot := nil;
    if ExtRoot = nil then
      ExtRoot := TJSONObject.Create;
    try
      MergeExtensionRecommendations(ExtRoot, SharedDefaults);
      WriteTextIfChanged(ExtFile, ExtRoot.Format, TEncoding.UTF8);
    finally
      ExtRoot.Free;
    end;
  finally
    SharedDefaults.Free;
  end;
end;

// Writes AContent to AFileName only if it differs from the current content.
// Leaving an unchanged file completely untouched matters for more than editor
// file-watcher noise: a version-control client that decides by timestamp
// reports a rewritten-but-identical file as locally modified.
procedure WriteTextIfChanged(const AFileName, AContent: string; AEncoding: TEncoding);
begin
  try
    if TFile.Exists(AFileName) and (TFile.ReadAllText(AFileName, AEncoding) = AContent) then
      Exit;
  except
    // Existing file unreadable: fall through and rewrite it.
  end;
  TFile.WriteAllText(AFileName, AContent, AEncoding);
end;

function GetDelphiBaseRegistryKey: string;
begin
  Result := '';
  var Services := BorlandIDEServices as IOTAServices;
  if Services = nil then
    Exit;
  Result := Services.GetBaseRegistryKey;
  if Result.StartsWith('\') then
    Result := Result.Substring(1);
end;

function GetDelphiVersionFromRegistry: string;
begin
  Result := '';
  var BaseKey := GetDelphiBaseRegistryKey;
  if BaseKey = '' then
    Exit;

  var SeparatorPos := LastDelimiter('\', BaseKey);
  if SeparatorPos <= 0 then
    Exit;
  Result := Copy(BaseKey, SeparatorPos + 1, MaxInt);
end;

function ExpandDelphiMacros(const APath: string): string; forward;

// User-defined IDE macros (Tools > Options > Environment Variables), which live
// only in the IDE's registry hive and are NOT necessarily in the process
// environment. Library and browsing paths routinely refer to them, and an entry
// whose macro does not expand is discarded, so without this the directory is
// silently never searched.
function GetIdeEnvironmentVariable(const AName: string): string;
begin
  Result := '';
  var BaseKey := GetDelphiBaseRegistryKey;
  if BaseKey = '' then
    Exit;
  var Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(BaseKey + '\Environment Variables') then
      try
        if Reg.ValueExists(AName) then
          Result := Reg.ReadString(AName);
      finally
        Reg.CloseKey;
      end;
  finally
    Reg.Free;
  end;
end;

// Guards the mutual recursion between macro expansion and this fallback. An IDE
// variable may be defined in terms of others, and self-reference is normal:
// the IDE ships PATH = "$(PUBLIC)\...;$(PATH)". Depth-limited rather than
// cycle-detecting, because the caller already discards anything still holding
// an unexpanded macro.
threadvar
  GMacroExpansionDepth: Integer;

function ResolveDelphiMacroFallback(const AMacroName: string): string;
begin
  Result := '';

  if SameText(AMacroName, 'BDS') then begin
    var IdeExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    if IdeExeDir <> '' then
      Exit(IdeExeDir);
    Exit;
  end;

  if SameText(AMacroName, 'BDSCOMMONDIR') then begin
    var PublicDir := GetEnvironmentVariable('PUBLIC');
    var DelphiVersion := GetDelphiVersionFromRegistry;
    if (PublicDir = '') or (DelphiVersion = '') then
      Exit;
    Exit(TPath.Combine(PublicDir, TPath.Combine('Documents\Embarcadero\Studio', DelphiVersion)));
  end;

  if SameText(AMacroName, 'BDSLIB') then begin
    var BdsDir := ResolveDelphiMacroFallback('BDS');
    if BdsDir = '' then
      Exit;
    Exit(TPath.Combine(BdsDir, 'lib'));
  end;

  Result := GetIdeEnvironmentVariable(AMacroName);
  if (Result <> '') and Result.Contains('$(') and (GMacroExpansionDepth < 4) then begin
    Inc(GMacroExpansionDepth);
    try
      Result := ExpandDelphiMacros(Result);
    finally
      Dec(GMacroExpansionDepth);
    end;
  end;
end;

// Expands Delphi make-style macros like $(BDS), $(BDSLIB) by reading env vars,
// falling back to derived values when the variable is not in the environment.
function ExpandDelphiMacros(const APath: string): string;
var
  S, MacroName: string;
  P1, P2: Integer;
begin
  S := APath;
  Result := '';
  var Pos := 1;
  while True do begin
    P1 := S.IndexOf('$(', Pos - 1);
    if P1 < 0 then begin
      Result := Result + S.Substring(Pos - 1);
      Break;
    end;
    Result := Result + S.Substring(Pos - 1, P1 - (Pos - 1));
    P2 := S.IndexOf(')', P1 + 2);
    if P2 < 0 then begin
      Result := Result + S.Substring(P1);
      Break;
    end;
    MacroName := S.Substring(P1 + 2, P2 - P1 - 2);
    var EnvVal := GetEnvironmentVariable(MacroName);
    if EnvVal = '' then
      EnvVal := ResolveDelphiMacroFallback(MacroName);
    if EnvVal <> '' then
      Result := Result + EnvVal
    else
      Result := Result + '$(' + MacroName + ')';
    Pos := P2 + 2;
  end;
end;

function NormalizePathForJson(const APath: string): string;
begin
  Result := StringReplace(Trim(APath), '\', '/', [rfReplaceAll]);
  while (Result <> '') and (Result[High(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

function ExpandProjectMacros(const ARawPath, AProjectDir, AProjectName,
  APlatformName, AConfigName: string): string;
begin
  Result := ARawPath;
  Result := StringReplace(Result, '$(Platform)', APlatformName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(Config)', AConfigName, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(ProjectDir)', AProjectDir, [rfReplaceAll, rfIgnoreCase]);
  Result := StringReplace(Result, '$(ProjectName)', AProjectName, [rfReplaceAll, rfIgnoreCase]);
  Result := ExpandDelphiMacros(Result);
end;

procedure GetActiveProjectBuildContext(AProject: IOTAProject;
  out AProjectDir, AProjectName, APlatformName, AConfigName: string);
var
  Confs: IOTAProjectOptionsConfigurations140;
begin
  AProjectDir := '';
  AProjectName := '';
  APlatformName := 'Win64';
  AConfigName := 'Debug';
  if AProject = nil then
    Exit;

  AProjectDir := IncludeTrailingPathDelimiter(ExtractFilePath(AProject.FileName));
  AProjectName := ChangeFileExt(ExtractFileName(AProject.FileName), '');

  if Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations140, Confs) then begin
    var ActiveConfig := Confs.ActiveConfiguration;
    if ActiveConfig <> nil then begin
      if Trim(ActiveConfig.Platform) <> '' then
        APlatformName := ActiveConfig.Platform;
      if Trim(ActiveConfig.Name) <> '' then
        AConfigName := ActiveConfig.Name;
    end;
  end;
end;

function GetProjectOptionValue(AProject: IOTAProject; const AOptionName: string): string;
var
  Confs: IOTAProjectOptionsConfigurations140;
begin
  Result := '';
  if AProject = nil then
    Exit;

  if Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations140, Confs) then begin
    var ActiveConfig := Confs.ActiveConfiguration;
    if ActiveConfig <> nil then begin
      Result := Trim(ActiveConfig.GetValue(AOptionName, True));
      if Result = '' then
        Result := Trim(ActiveConfig.GetValue(AOptionName, False));
    end;
  end;

  if Result = '' then begin
    var Opts := AProject.GetProjectOptions;
    if Opts <> nil then
      Result := Trim(VarToStrDef(Opts.GetOptionValue(AOptionName), ''));
  end;
end;

function ResolveProjectOutputDir(AProject: IOTAProject; const AOptionName,
  AFallbackRelative: string): string;
var
  ProjectDir, ProjectName, PlatformName, ConfigName: string;
  RawPath, FullPath: string;
begin
  Result := '';
  if AProject = nil then
    Exit;

  GetActiveProjectBuildContext(AProject, ProjectDir, ProjectName, PlatformName, ConfigName);

  RawPath := GetProjectOptionValue(AProject, AOptionName);
  if RawPath = '' then
    RawPath := AFallbackRelative;

  RawPath := ExpandProjectMacros(RawPath, ProjectDir, ProjectName, PlatformName, ConfigName);
  if RawPath = '' then
    Exit;

  FullPath := RawPath;
  if not TPath.IsPathRooted(FullPath) then
    FullPath := TPath.Combine(ProjectDir, FullPath);
  FullPath := TPath.GetFullPath(FullPath);
  Result := NormalizePathForJson(FullPath);
end;

function ResolveProjectOptionPathList(AProject: IOTAProject;
  const AOptionName: string): TArray<string>;
var
  ProjectDir, ProjectName, PlatformName, ConfigName: string;
  RawList: string;
begin
  Result := [];
  if AProject = nil then
    Exit;

  RawList := GetProjectOptionValue(AProject, AOptionName);
  if RawList = '' then
    Exit;

  GetActiveProjectBuildContext(AProject, ProjectDir, ProjectName, PlatformName, ConfigName);

  for var RawPart in RawList.Split([';']) do begin
    var Part := Trim(RawPart);
    if Part = '' then
      Continue;
    Part := ExpandProjectMacros(Part, ProjectDir, ProjectName, PlatformName, ConfigName);
    if Part = '' then
      Continue;
    if not TPath.IsPathRooted(Part) then
      Part := TPath.Combine(ProjectDir, Part);
    Part := NormalizePathForJson(TPath.GetFullPath(Part));
    if Part = '' then
      Continue;

    var AlreadyAdded := False;
    for var Existing in Result do
      if SameText(Existing, Part) then begin
        AlreadyAdded := True;
        Break;
      end;
    if not AlreadyAdded then
      Result := Result + [Part];
  end;
end;

function ResolveIdePackageOutputDirs(AProject: IOTAProject): TArray<string>;
var
  ProjectDir, ProjectName, PlatformName, ConfigName: string;
  BaseKey: string;
  PlatformsToScan: TArray<string>;

  procedure AddDirFromRawValue(const ARawValue: string);
  begin
    var Expanded := Trim(ARawValue);
    if Expanded = '' then
      Exit;

    Expanded := ExpandProjectMacros(Expanded, ProjectDir, ProjectName, PlatformName, ConfigName);
    if Expanded = '' then
      Exit;
    Expanded := StringReplace(Expanded, '/', '\', [rfReplaceAll]);
    if Pos('$(', Expanded) > 0 then
      Exit;
    if not TPath.IsPathRooted(Expanded) then
      Exit;

    Expanded := NormalizePathForJson(TPath.GetFullPath(Expanded));
    if Expanded = '' then
      Exit;

    for var Existing in Result do
      if SameText(Existing, Expanded) then
        Exit;
    Result := Result + [Expanded];
  end;

begin
  Result := [];
  if AProject = nil then
    Exit;

  GetActiveProjectBuildContext(AProject, ProjectDir, ProjectName, PlatformName, ConfigName);
  BaseKey := GetDelphiBaseRegistryKey;
  if BaseKey = '' then
    Exit;

  PlatformsToScan := [PlatformName];
  if not SameText(PlatformName, 'Win64') then
    PlatformsToScan := PlatformsToScan + ['Win64'];

  var Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    for var PlatformToScan in PlatformsToScan do begin
      var LibraryKey := BaseKey + '\Library\' + PlatformToScan;
      if not Reg.OpenKeyReadOnly(LibraryKey) then
        Continue;
      try
        if Reg.ValueExists('Package DPL Output') then
          AddDirFromRawValue(Reg.ReadString('Package DPL Output'));
        if Reg.ValueExists('Package DCP Output') then
          AddDirFromRawValue(Reg.ReadString('Package DCP Output'));
      finally
        Reg.CloseKey;
      end;
      if Length(Result) > 0 then
        Break;
    end;
  finally
    Reg.Free;
  end;
end;

function ResolveProjectOutputFile(AProject: IOTAProject; const AFileName: string;
  const ACandidateOptions: array of string; const ADefaultOption,
  AFallbackRelative: string; const AExtraDirs: array of string): string;
var
  CandidateDirs: TArray<string>;

  procedure AddCandidate(const ADir: string);
  begin
    if ADir = '' then
      Exit;
    for var Existing in CandidateDirs do
      if SameText(Existing, ADir) then
        Exit;
    CandidateDirs := CandidateDirs + [ADir];
  end;

begin
  CandidateDirs := [];
  for var Opt in ACandidateOptions do
    AddCandidate(ResolveProjectOutputDir(AProject, Opt, AFallbackRelative));

  for var Dir in ResolveIdePackageOutputDirs(AProject) do
    AddCandidate(Dir);

  for var Dir in ResolveProjectOptionPathList(AProject, sUnitSearchPath) do
    AddCandidate(Dir);
  for var Dir in ResolveProjectOptionPathList(AProject, sLibraryPath) do
    AddCandidate(Dir);
  for var Dir in AExtraDirs do
    AddCandidate(NormalizePathForJson(Dir));

  if Length(CandidateDirs) = 0 then
    AddCandidate(ResolveProjectOutputDir(AProject, ADefaultOption, AFallbackRelative));

  for var Dir in CandidateDirs do begin
    var Candidate := TPath.Combine(StringReplace(Dir, '/', PathDelim, [rfReplaceAll]), AFileName);
    if TFile.Exists(Candidate) then
      Exit(NormalizePathForJson(Candidate));
  end;

  if Length(CandidateDirs) > 0 then begin
    var FirstCandidate := TPath.Combine(StringReplace(CandidateDirs[0], '/', PathDelim, [rfReplaceAll]), AFileName);
    Exit(NormalizePathForJson(FirstCandidate));
  end;

  Result := NormalizePathForJson(AFileName);
end;

// Collects all source search paths visible to Delphi for AProject:
//   - $(BDS)\source
//   - project-level DCC_UnitSearchPath, for the ACTIVE build configuration
//   - the IDE's global "Search Path" for the project's platform (registry)
//   - the IDE's global "Browsing Path" for that platform (registry)
// There is deliberately no project-level browsing path: Delphi has none.
// DCCStrs.pas declares Include/Obj/Resource/UnitSearch/Framework/Library and
// nothing else, and no .dproj carries such a setting - it is an IDE-wide,
// per-platform value only.
// Returns a JSON array of forward-slash absolute paths ready for launch.json.
function CollectSourceSearchPaths(AProject: IOTAProject): TJSONArray;
var
  Seen: TDictionary<string, Boolean>;
  ProjectDir, ProjectName, PlatformName, ConfigName: string;

  // Resolves one raw search-path entry to an absolute, forward-slash path.
  // The entry arrives straight from the project options or the IDE registry,
  // so it may be relative and may still contain Delphi macros.
  procedure AddPath(const APath: string);
  var
    Norm: string;
  begin
    Norm := Trim(APath);
    if Norm = '' then
      Exit;
    // Expand the full project macro set, not just the environment/BDS ones:
    // a library or unit search path routinely contains $(Platform), $(Config)
    // or $(ProjectDir). An unexpanded macro that reaches launch.json is not
    // understood by VS Code and is discarded by the debug adapter, so the
    // directory is silently never searched.
    Norm := ExpandProjectMacros(Norm, ProjectDir, ProjectName, PlatformName, ConfigName);
    if (Norm = '') or Norm.Contains('$(') then
      Exit;
    // A relative entry is relative to the project directory, exactly as the
    // compiler resolves it.
    if not TPath.IsPathRooted(Norm) then begin
      if ProjectDir = '' then
        Exit;
      Norm := TPath.Combine(ProjectDir, Norm);
    end;
    try
      Norm := NormalizePathForJson(TPath.GetFullPath(Norm));
    except
      Exit; // malformed entry (e.g. stale registry value): skip it
    end;
    if (Norm = '') or Seen.ContainsKey(LowerCase(Norm)) then
      Exit;
    Seen.Add(LowerCase(Norm), True);
    Result.Add(Norm);
  end;

  procedure AddSemicolonList(const AList: string);
  begin
    for var Part in AList.Split([';']) do
      AddPath(Part);
  end;

begin
  Result := TJSONArray.Create;
  Seen := TDictionary<string, Boolean>.Create;
  GetActiveProjectBuildContext(AProject, ProjectDir, ProjectName, PlatformName, ConfigName);
  try
    // Write the literal expanded BDS path -- VS Code cannot expand ${env:BDS}
    // unless BDS is in VS Code's own process environment (it is not).
    var BdsDir := GetEnvironmentVariable('BDS');
    if BdsDir <> '' then
      AddPath(BdsDir + '\source');

    // Project-level paths. Read through GetProjectOptionValue so the ACTIVE
    // build configuration wins: the raw IOTAProjectOptions getter returns the
    // project-wide value and misses per-configuration overrides.
    //
    // The include path belongs here as much as the unit search path does. Code
    // inside a `{$I foo.inc}` is attributed to foo.inc in the line table, not to
    // the unit that includes it - one real project's map carries 654 such
    // references - so stopping on such a line means the debugger has to find the
    // .inc on disk, and this is where it is declared.
    //
    // Of the six path options Delphi declares per project (DCCStrs.pas:
    // Include/Obj/Resource/UnitSearch/Framework/Library), these two are the only
    // ones that name SOURCE directories; the rest point at .obj, .res,
    // frameworks and libraries. There is no per-project browsing path.
    if AProject <> nil then begin
      AddSemicolonList(GetProjectOptionValue(AProject, sUnitSearchPath));
      AddSemicolonList(GetProjectOptionValue(AProject, sIncludePath));
    end;

    // Global library / source paths stored by the IDE in the registry, for the
    // platform the project actually builds for (PlatformName defaults to Win64).
    var Services := BorlandIDEServices as IOTAServices;
    if Services <> nil then begin
      var BaseKey := Services.GetBaseRegistryKey;
      if BaseKey.StartsWith('\') then
        BaseKey := BaseKey.Substring(1);
      var Reg := TRegistry.Create(KEY_READ);
      try
        Reg.RootKey := HKEY_CURRENT_USER;
        if Reg.OpenKeyReadOnly(BaseKey + '\Library\' + PlatformName) then
          try
            if Reg.ValueExists('Search Path') then
              AddSemicolonList(Reg.ReadString('Search Path'));
            // The browsing path matters MORE than the search path here. Delphi
            // uses the search path to find compiled units and the browsing path
            // to find the SOURCES that go with them - which is exactly what a
            // debugger needs to show you a line it has already resolved.
            // Measured on one real installation: 89 of the 91 browsing entries
            // appear nowhere in the search path, and 37 of those are
            // third-party source trees. Without them the debugger resolves a
            // frame in, say, a component library and then cannot display it.
            if Reg.ValueExists('Browsing Path') then
              AddSemicolonList(Reg.ReadString('Browsing Path'));
          finally
            Reg.CloseKey;
          end;
      finally
        Reg.Free;
      end;
    end;
  finally
    Seen.Free;
  end;
end;

procedure AddSearchPathIfMissing(APaths: TJSONArray; const APath: string);
begin
  if APaths = nil then
    Exit;

  var Norm := Trim(APath);
  if Norm = '' then
    Exit;
  Norm := StringReplace(Norm, '\', '/', [rfReplaceAll]);
  while (Norm <> '') and (Norm[High(Norm)] = '/') do
    SetLength(Norm, Length(Norm) - 1);
  if Norm = '' then
    Exit;

  for var I := 0 to APaths.Count - 1 do begin
    var V := APaths.Items[I];
    if (V <> nil) and SameText(StringReplace(V.Value, '\', '/', [rfReplaceAll]), Norm) then
      Exit;
  end;

  APaths.Add(Norm);
end;

const
  // VS Code substitutes this before the configuration reaches the debug adapter,
  // so the generated file carries no machine-specific root.
  WORKSPACE_FOLDER_MACRO = '${workspaceFolder}';

// Rewrites an absolute path relative to the workspace root when it can be
// expressed that way, so the generated configuration does not depend on where
// the sources happen to be checked out. A dependency kept beside the workspace
// becomes "${workspaceFolder}/../shared/lib".
//
// The relative form is DERIVED from the real paths, never assumed: a path on a
// different drive, or one with no common root, is left absolute, which is still
// correct - only less portable.
function MakePathWorkspaceRelative(const APath, AWorkspaceDir: string): string;
begin
  Result := NormalizePathForJson(APath);
  if (Result = '') or (AWorkspaceDir = '') or Result.StartsWith('$') then
    Exit;
  if not TPath.IsPathRooted(Result) then
    Exit;

  var Base := IncludeTrailingPathDelimiter(
    StringReplace(NormalizePathForJson(AWorkspaceDir), '/', '\', [rfReplaceAll]));
  var Dest := StringReplace(Result, '/', '\', [rfReplaceAll]);
  if not SameText(ExtractFileDrive(Base), ExtractFileDrive(Dest)) then
    Exit;

  // The path IS the workspace root (the common case for sourceRoot).
  // ExtractRelativePath treats the last segment as a file name and would answer
  // "..\<rootname>", which silently breaks the moment the project is checked out
  // into a differently named folder.
  if SameText(ExcludeTrailingPathDelimiter(Base), Dest) then
    Exit(WORKSPACE_FOLDER_MACRO);

  var Rel := ExtractRelativePath(Base, Dest);
  if (Rel = '') or TPath.IsPathRooted(Rel) then
    Exit;

  Rel := NormalizePathForJson(Rel);
  if Rel.StartsWith('./') then
    Rel := Rel.Substring(2);
  if (Rel = '') or (Rel = '.') then
    Exit(WORKSPACE_FOLDER_MACRO);
  Result := WORKSPACE_FOLDER_MACRO + '/' + Rel;
end;

// Applies MakePathWorkspaceRelative to every path a delphi-win64 configuration
// carries. Called once on the finished configuration, where the workspace root
// is known - CollectSourceSearchPaths itself has no way to know it.
procedure MakeLaunchConfigPortable(AConfig: TJSONObject; const AWorkspaceDir: string);

  procedure RewritePathPair(AObj: TJSONObject; const AName: string);
  begin
    if AObj = nil then
      Exit;
    var Value := AObj.GetValue(AName);
    if not (Value is TJSONString) then
      Exit;
    var Portable := MakePathWorkspaceRelative(Value.Value, AWorkspaceDir);
    if Portable = Value.Value then
      Exit;
    AObj.RemovePair(AName).Free;
    AObj.AddPair(AName, Portable);
  end;

begin
  if (AConfig = nil) or (AWorkspaceDir = '') then
    Exit;

  for var PairName in ['program', 'sourceRoot', 'mapFile', 'rsmFile'] do
    RewritePathPair(AConfig, PairName);

  var Paths := AConfig.GetValue('sourceSearchPaths');
  if Paths is TJSONArray then begin
    var Portable := TJSONArray.Create;
    for var I := 0 to TJSONArray(Paths).Count - 1 do
      Portable.Add(MakePathWorkspaceRelative(TJSONArray(Paths).Items[I].Value, AWorkspaceDir));
    AConfig.RemovePair('sourceSearchPaths').Free;
    AConfig.AddPair('sourceSearchPaths', Portable);
  end;

  var Modules := AConfig.GetValue('modules');
  if Modules is TJSONArray then
    for var Item in TJSONArray(Modules) do
      if Item is TJSONObject then
        for var PairName in ['map', 'rsm', 'dcp'] do
          RewritePathPair(TJSONObject(Item), PairName);
end;

function GetCommonPathPrefixNormalized(const APath1, APath2: string): string;
begin
  Result := '';
  var LeftPath := Trim(APath1);
  var RightPath := Trim(APath2);
  if (LeftPath = '') or (RightPath = '') then
    Exit;

  LeftPath := StringReplace(LeftPath, '/', PathDelim, [rfReplaceAll]);
  RightPath := StringReplace(RightPath, '/', PathDelim, [rfReplaceAll]);
  if not TPath.IsPathRooted(LeftPath) or not TPath.IsPathRooted(RightPath) then
    Exit;

  LeftPath := ExcludeTrailingPathDelimiter(TPath.GetFullPath(LeftPath));
  RightPath := ExcludeTrailingPathDelimiter(TPath.GetFullPath(RightPath));

  var LeftRoot := IncludeTrailingPathDelimiter(TPath.GetPathRoot(LeftPath));
  var RightRoot := IncludeTrailingPathDelimiter(TPath.GetPathRoot(RightPath));
  if (LeftRoot = '') or (RightRoot = '') then
    Exit;
  if not SameText(LeftRoot, RightRoot) then
    Exit;

  var LeftRest := Copy(LeftPath, Length(LeftRoot) + 1, MaxInt);
  var RightRest := Copy(RightPath, Length(RightRoot) + 1, MaxInt);

  var LeftParts := LeftRest.Split([PathDelim], TStringSplitOptions.ExcludeEmpty);
  var RightParts := RightRest.Split([PathDelim], TStringSplitOptions.ExcludeEmpty);

  var MaxCommon := Length(LeftParts);
  if Length(RightParts) < MaxCommon then
    MaxCommon := Length(RightParts);

  var CommonPath := LeftRoot;
  for var Index := 0 to MaxCommon - 1 do begin
    if not SameText(LeftParts[Index], RightParts[Index]) then
      Break;
    CommonPath := TPath.Combine(CommonPath, LeftParts[Index]);
  end;
  Result := NormalizePathForJson(ExcludeTrailingPathDelimiter(CommonPath));
end;

function GetPackageSourceRoot(const AProjectDir, AExpandedHostApp,
  ASourceRootOverride: string): string;
begin
  Result := NormalizePathForJson(ASourceRootOverride);
  if Result <> '' then
    Exit;

  Result := NormalizePathForJson(AProjectDir);
  if Result = '' then
    Exit;

  if AExpandedHostApp = '' then
    Exit;
  if Pos('$(', AExpandedHostApp) > 0 then
    Exit;

  var HostPath := StringReplace(AExpandedHostApp, '/', PathDelim, [rfReplaceAll]);
  if not TPath.IsPathRooted(HostPath) then
    Exit;

  var HostDir := NormalizePathForJson(ExtractFileDir(HostPath));
  if HostDir = '' then
    Exit;

  var CommonRoot := GetCommonPathPrefixNormalized(Result, HostDir);
  if CommonRoot = '' then
    Exit;
  if (Length(CommonRoot) <= 3) and (Pos(':', CommonRoot) > 0) then
    Exit;
  Result := CommonRoot;
end;

function GetProjectHostApplication(AProject: IOTAProject): string;
var
  Opts: IOTAProjectOptions;
  Val: Variant;
  Confs: IOTAProjectOptionsConfigurations140;
  ProjectDir, ProjectName, PlatformName, ConfigName, RawHostApp: string;
begin
  Result := '';
  if AProject = nil then
    Exit;

  ProjectDir := IncludeTrailingPathDelimiter(ExtractFilePath(AProject.FileName));
  ProjectName := ChangeFileExt(ExtractFileName(AProject.FileName), '');
  PlatformName := 'Win64';
  ConfigName := 'Debug';

  if Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations140, Confs) then begin
    var ActiveConfig := Confs.ActiveConfiguration;
    if ActiveConfig <> nil then begin
      PlatformName := ActiveConfig.Platform;
      ConfigName := ActiveConfig.Name;

      RawHostApp := Trim(ActiveConfig.GetValue(sDebugger_HostApplication, True));
      if RawHostApp <> '' then
        Exit(ExpandProjectMacros(RawHostApp, ProjectDir, ProjectName, PlatformName, ConfigName));

      RawHostApp := Trim(ActiveConfig.GetValue(sDebugger_HostApplication, False));
      if RawHostApp <> '' then
        Exit(ExpandProjectMacros(RawHostApp, ProjectDir, ProjectName, PlatformName, ConfigName));
    end;
  end;

  Opts := AProject.GetProjectOptions;
  if Opts = nil then
    Exit;
  Val := Opts.GetOptionValue(sDebugger_HostApplication);
  RawHostApp := Trim(VarToStrDef(Val, ''));
  if RawHostApp = '' then
    Exit;
  Result := ExpandProjectMacros(RawHostApp, ProjectDir, ProjectName, PlatformName, ConfigName);
end;

function BuildProgramLaunchConfig(const AProjectName, APreLaunchTask, AProjectDir: string;
  AProject: IOTAProject): TJSONObject;
var
  Base: string;
  ProgramPath, MapPath, RsmPath: string;
  SearchPaths: TJSONArray;
begin
  Base := StringReplace(AProjectDir, '\', '/', [rfReplaceAll]);
  ProgramPath := ResolveProjectOutputFile(AProject, AProjectName + '.exe',
    [sExeOutput], sExeOutput, '.\\$(Platform)\\$(Config)', []);
  MapPath := ResolveProjectOutputFile(AProject, AProjectName + '.map',
    [sExeOutput, sBplOutput], sExeOutput, '.\\$(Platform)\\$(Config)', []);
  RsmPath := ResolveProjectOutputFile(AProject, AProjectName + '.rsm',
    [sExeOutput, sDcpOutput, sDcuOutput], sExeOutput, '.\\$(Platform)\\$(Config)', []);

  Result := TJSONObject.Create;
  Result.AddPair('type', 'delphi-win64');
  Result.AddPair('request', 'launch');
  Result.AddPair('name', 'Debug ' + AProjectName);
  if APreLaunchTask <> '' then
    Result.AddPair('preLaunchTask', APreLaunchTask);
  Result.AddPair('program', ProgramPath);
  Result.AddPair('mapFile', MapPath);
  Result.AddPair('rsmFile', RsmPath);
  Result.AddPair('sourceRoot', Base);
  SearchPaths := CollectSourceSearchPaths(AProject);
  AddSearchPathIfMissing(SearchPaths, Base);
  Result.AddPair('sourceSearchPaths', SearchPaths);
  // Set here rather than when the configuration is stored: stopAtEntry belongs
  // to a launch request only, and the storing code now also handles an attach
  // configuration, for which the property is meaningless.
  Result.AddPair('stopAtEntry', TJSONBool.Create(False));
end;

function BuildPackageLaunchConfig(const AProjectName, AProjectDir, AHostAppPath, APreLaunchTask: string;
  AProject: IOTAProject; const ASourceRootOverride: string = ''): TJSONObject;
var
  ExpandedHostApp, HostMapFile, ProjBase, SourceRoot: string;
  MapPath, RsmPath, DcpPath: string;
  HostOutputDir: string;
  SearchPaths: TJSONArray;
begin
  if Pos('$(', AHostAppPath) > 0 then
    ExpandedHostApp := AHostAppPath
  else if TPath.IsRelativePath(AHostAppPath) then
    ExpandedHostApp := TPath.GetFullPath(TPath.Combine(AProjectDir, AHostAppPath))
  else
    ExpandedHostApp := AHostAppPath;
  ExpandedHostApp := StringReplace(ExpandedHostApp, '\', '/', [rfReplaceAll]);

  Result := TJSONObject.Create;
  Result.AddPair('type', 'delphi-win64');
  Result.AddPair('request', 'launch');
  Result.AddPair('name', 'Debug ' + AProjectName + ' (BPL)');
  if APreLaunchTask <> '' then
    Result.AddPair('preLaunchTask', APreLaunchTask);
  Result.AddPair('program', ExpandedHostApp);

  HostMapFile := ChangeFileExt(ExpandedHostApp, '.map');
  if TFile.Exists(StringReplace(HostMapFile, '/', '\', [rfReplaceAll])) then
    Result.AddPair('mapFile', HostMapFile);

  HostOutputDir := NormalizePathForJson(ExtractFileDir(ExpandedHostApp));

  ProjBase := StringReplace(AProjectDir, '\', '/', [rfReplaceAll]);
  SourceRoot := GetPackageSourceRoot(ProjBase, ExpandedHostApp, ASourceRootOverride);
  Result.AddPair('sourceRoot', SourceRoot);
  SearchPaths := CollectSourceSearchPaths(AProject);
  AddSearchPathIfMissing(SearchPaths, SourceRoot);
  AddSearchPathIfMissing(SearchPaths, ProjBase);
  AddSearchPathIfMissing(SearchPaths, HostOutputDir);
  Result.AddPair('sourceSearchPaths', SearchPaths);

  MapPath := ResolveProjectOutputFile(AProject, AProjectName + '.map',
    [sBplOutput, sExeOutput], sBplOutput, '.\\$(Platform)\\$(Config)', [HostOutputDir]);
  RsmPath := ResolveProjectOutputFile(AProject, AProjectName + '.rsm',
    [sBplOutput, sDcpOutput, sExeOutput], sBplOutput, '.\\$(Platform)\\$(Config)', [HostOutputDir]);
  DcpPath := ResolveProjectOutputFile(AProject, AProjectName + '.dcp',
    [sDcpOutput, sBplOutput, sExeOutput], sDcpOutput, '.\\$(Platform)\\$(Config)', [HostOutputDir]);

  var ModEntry := TJSONObject.Create;
  // Use "AProjectName + '.bpl'", NOT ExtractFileName(BplPath): BplPath is already
  // forward-slash normalized for JSON, and ExtractFileName splits only on '\' and
  // ':', so on "C:/.../libFoo.bpl" it returns "/.../libFoo.bpl" -- a malformed name
  // the adapter then fails to match to the loaded module.
  ModEntry.AddPair('name', AProjectName + '.bpl');
  ModEntry.AddPair('map', MapPath);
  ModEntry.AddPair('rsm', RsmPath);
  ModEntry.AddPair('dcp', DcpPath);
  var Modules := TJSONArray.Create;
  Modules.Add(ModEntry);
  Result.AddPair('modules', Modules);
  // See BuildProgramLaunchConfig: launch-only property, set by the builder.
  Result.AddPair('stopAtEntry', TJSONBool.Create(False));
end;

// Extracts the file name from a path already normalized for JSON.
// ExtractFileName splits on '\' and ':' only, so on "C:/out/Foo.exe" it would
// answer "/out/Foo.exe"; the separators have to be converted back first.
function ExtractFileNameFromJsonPath(const AJsonPath: string): string;
begin
  Result := ExtractFileName(StringReplace(AJsonPath, '/', PathDelim, [rfReplaceAll]));
end;

// Builds the attach configuration matching ALaunchConfig, or nil when the launch
// configuration names no executable.
//
// It is DERIVED from the finished launch configuration instead of resolving the
// project options a second time. Reusing the values is the whole point of
// generating the entry at all: sourceRoot, sourceSearchPaths and modules are
// what nobody wants to write by hand, and copying them makes it structurally
// impossible for the two configurations to drift apart.
function BuildAttachConfig(ALaunchConfig: TJSONObject): TJSONObject;
begin
  Result := nil;
  if ALaunchConfig = nil then
    Exit;

  var ProgramPath := ALaunchConfig.GetValue<string>('program', '');
  if ProgramPath = '' then
    Exit;
  // The launch "program" already IS the process the user would attach to: the
  // project output for a .dpr, the Host application for a .dpk.
  var ExeName := ExtractFileNameFromJsonPath(ProgramPath);
  if ExeName = '' then
    Exit;

  Result := TJSONObject.Create;
  Result.AddPair('type', 'delphi-win64');
  Result.AddPair('request', 'attach');
  Result.AddPair('name', 'Attach to ' + ExeName);
  Result.AddPair('processName', ExeName);
  // Optional for the adapter, but worth writing: it derives the .map/.rsm from
  // this path, so symbols still resolve when the running image is a copy
  // deployed somewhere other than the build output directory.
  Result.AddPair('program', ProgramPath);
  // Detaching leaves the application running. Attaching is a diagnostic step on
  // a process the debugger does not own, so killing it on stop would be wrong.
  Result.AddPair('killOnDetach', TJSONBool.Create(False));

  // The symbol/source properties are shared verbatim with the launch entry.
  for var PairName in ['sourceRoot', 'sourceSearchPaths', 'modules'] do begin
    var Value := ALaunchConfig.GetValue(PairName);
    if Value <> nil then
      Result.AddPair(PairName, Value.Clone as TJSONValue);
  end;
end;

// Stores ANewConfigs into AConfigs as THE plugin-managed set, replacing the
// previous generation. User-authored configurations are preserved.
//
// The managed set is keyed by name: the plugin writes more than one entry
// (launch + attach), so removing "every managed entry" once per entry would make
// the second write delete the first. Everything is therefore removed once, up
// front, and the new set appended in the given order.
procedure UpsertManagedDebugConfigs(AConfigs: TJSONArray; const ANewConfigs: array of TJSONObject);
var
  NewNames: TArray<string>;

  function IsOneOfTheNewNames(const AName: string): Boolean;
  begin
    for var NewName in NewNames do
      if SameText(NewName, AName) then
        Exit(True);
    Result := False;
  end;

begin
  NewNames := [];
  for var NewConfig in ANewConfigs do
    NewNames := NewNames + [NewConfig.GetValue<string>('name', '')];

  for var I := AConfigs.Count - 1 downto 0 do begin
    var Item := AConfigs.Items[I] as TJSONObject;
    if Item = nil then
      Continue;
    var TypeVal := Item.GetValue('type');
    if (TypeVal = nil) or not SameText(TypeVal.Value, 'delphi-win64') then
      Continue;
    // A managed entry always goes, whatever its name: that also clears entries
    // left behind by a renamed project or by an older plugin version. A
    // user-authored entry goes only when it claims one of the names about to be
    // written, because two configurations cannot share a name.
    var ManagedVal := Item.GetValue(PLUGIN_MANAGED_BY_FIELD);
    var IsManaged := (ManagedVal <> nil) and SameText(ManagedVal.Value, PLUGIN_MANAGED_BY_VALUE);
    var NameVal := Item.GetValue('name');
    var ClaimsManagedName := (NameVal <> nil) and IsOneOfTheNewNames(NameVal.Value);
    if IsManaged or ClaimsManagedName then
      AConfigs.Remove(I).Free;
  end;

  for var NewConfig in ANewConfigs do begin
    NewConfig.AddPair(PLUGIN_MANAGED_BY_FIELD, PLUGIN_MANAGED_BY_VALUE);
    AConfigs.Add(NewConfig);
  end;
end;

// Makes ALaunchConfig portable, derives the matching attach configuration and
// stores both as the managed set.
// AWorkspaceDir empty means the workspace root is ambiguous (several roots), in
// which case the paths are left absolute.
procedure UpsertManagedDebugConfigsFor(AConfigs: TJSONArray; ALaunchConfig: TJSONObject;
  const AWorkspaceDir: string);
begin
  var AttachConfig: TJSONObject := nil;
  if TPluginSettings.GenerateAttachConfig then
    AttachConfig := BuildAttachConfig(ALaunchConfig);

  MakeLaunchConfigPortable(ALaunchConfig, AWorkspaceDir);
  MakeLaunchConfigPortable(AttachConfig, AWorkspaceDir);

  // The launch entry must stay first: VS Code preselects the first
  // configuration, so F5 keeps starting the program with no extra choice.
  if AttachConfig = nil then
    UpsertManagedDebugConfigs(AConfigs, [ALaunchConfig])
  else
    UpsertManagedDebugConfigs(AConfigs, [ALaunchConfig, AttachConfig]);
end;

// Writes ALaunchConfig, plus the attach configuration derived from it, into
// AProjectDir\.vscode\launch.json. The existing "version" and any user
// configurations are preserved: only the plugin-managed entries are replaced.
procedure WriteManagedLaunchConfigToDir(const AProjectDir: string; ALaunchConfig: TJSONObject);
var
  VscodePath, LaunchFile: string;
  Root: TJSONObject;
begin
  VscodePath := IncludeTrailingPathDelimiter(AProjectDir) + '.vscode';
  if not TDirectory.Exists(VscodePath) then
    TDirectory.CreateDirectory(VscodePath);
  LaunchFile := VscodePath + '\launch.json';

  if TFile.Exists(LaunchFile) then
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(LaunchFile)) as TJSONObject
  else
    Root := nil;
  if Root = nil then
    Root := TJSONObject.Create;
  try
    if Root.GetValue('version') = nil then
      Root.AddPair('version', '0.2.0');
    var Configs := Root.GetValue('configurations') as TJSONArray;
    if Configs = nil then begin
      Configs := TJSONArray.Create;
      Root.AddPair('configurations', Configs);
    end;
    // Folder mode always has exactly one root, so ${workspaceFolder} is
    // unambiguous here and the generated paths stay checkout-independent.
    UpsertManagedDebugConfigsFor(Configs, ALaunchConfig, ExcludeTrailingPathDelimiter(AProjectDir));
    WriteTextIfChanged(LaunchFile, Root.Format, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

function BuildBuildTaskConfig(const AProjectName, AProjectFileName: string; AIsBpl: Boolean): TJSONObject;
var
  TaskLabel, DprojFile, MsBuildCmd: string;
begin
  if AIsBpl then
    TaskLabel := 'Build ' + AProjectName + ' BPL (Debug Win64)'
  else
    TaskLabel := 'Build ' + AProjectName + ' (Debug Win64)';
  DprojFile := ExtractFileName(AProjectFileName);
  MsBuildCmd := 'rsvars.bat && msbuild ' + DprojFile + ' /t:Build /p:Config=Debug;Platform=Win64 /nologo';

  Result := TJSONObject.Create;
  Result.AddPair('label', TaskLabel);
  Result.AddPair('type', 'shell');
  Result.AddPair('command', 'cmd');
  var Args := TJSONArray.Create;
  Args.Add('/c');
  Args.Add(MsBuildCmd);
  Result.AddPair('args', Args);
  var Options := TJSONObject.Create;
  var ProjectDir := StringReplace(ExcludeTrailingPathDelimiter(ExtractFilePath(AProjectFileName)), '\', '/', [rfReplaceAll]);
  Options.AddPair('cwd', ProjectDir);
  Result.AddPair('options', Options);
  var Presentation := TJSONObject.Create;
  Presentation.AddPair('reveal', 'always');
  Presentation.AddPair('panel', 'shared');
  Result.AddPair('presentation', Presentation);
  var Pattern := TJSONObject.Create;
  Pattern.AddPair('regexp', '^(.+)\((\d+)\)\s+(Fatal|Error|Warning|Hint):\s+[A-Z]\d+\s+(.+)$');
  Pattern.AddPair('file', TJSONNumber.Create(1));
  Pattern.AddPair('line', TJSONNumber.Create(2));
  Pattern.AddPair('severity', TJSONNumber.Create(3));
  Pattern.AddPair('message', TJSONNumber.Create(4));
  var ProblemMatcher := TJSONObject.Create;
  ProblemMatcher.AddPair('owner', 'delphi');
  ProblemMatcher.AddPair('fileLocation', 'absolute');
  ProblemMatcher.AddPair('pattern', Pattern);
  Result.AddPair('problemMatcher', ProblemMatcher);
end;

// group (including isDefault) is structural: refreshed on every upsert, not only on insert.
procedure UpsertTaskConfig(ATasks: TJSONArray; ATask: TJSONObject; AIsDefault: Boolean);
var
  ExistingTask: TJSONObject;
  TargetLabel: string;
begin
  TargetLabel := ATask.GetValue<string>('label', '');
  ExistingTask := nil;
  for var i := 0 to ATasks.Count - 1 do begin
    var Item := ATasks.Items[i] as TJSONObject;
    if (Item <> nil) and (Item.GetValue<string>('label', '') = TargetLabel) then begin
      ExistingTask := Item;
      Break;
    end;
  end;

  var GroupObj := TJSONObject.Create;
  GroupObj.AddPair('kind', 'build');
  GroupObj.AddPair('isDefault', TJSONBool.Create(AIsDefault));
  ATask.AddPair('group', GroupObj);

  if ExistingTask = nil then
    ATasks.Add(ATask)
  else begin
    for var Pair in ATask do begin
      ExistingTask.RemovePair(Pair.JsonString.Value).Free;
      ExistingTask.AddPair(Pair.JsonString.Value, Pair.JsonValue.Clone as TJSONValue);
    end;
    ATask.Free;
  end;
end;

// Removes plugin-generated build-task labels from a per-folder tasks.json.
// Used in workspace mode so per-folder tasks never compete in the task picker.
procedure CleanupPerFolderTasksJson(const AProjectDir, AProjectName: string; AIsBpl: Boolean);
var
  TasksFile: string;
  Root: TJSONObject;
  Tasks: TJSONArray;

  procedure RemoveByLabel(const ALabel: string);
  begin
    for var i := Tasks.Count - 1 downto 0 do begin
      var Item := Tasks.Items[i] as TJSONObject;
      if (Item <> nil) and (Item.GetValue<string>('label', '') = ALabel) then begin
        Tasks.Remove(i).Free;
        Break;
      end;
    end;
  end;

begin
  TasksFile := IncludeTrailingPathDelimiter(AProjectDir) + '.vscode\tasks.json';
  if not TFile.Exists(TasksFile) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(TasksFile)) as TJSONObject;
  if Root = nil then
    Exit;
  try
    Tasks := Root.GetValue('tasks') as TJSONArray;
    if Tasks <> nil then begin
      RemoveByLabel('Build All (Debug Win64)');
      if AIsBpl then
        RemoveByLabel('Build ' + AProjectName + ' BPL (Debug Win64)')
      else
        RemoveByLabel('Build ' + AProjectName + ' (Debug Win64)');
      WriteTextIfChanged(TasksFile, Root.Format, TEncoding.UTF8);
    end;
  finally
    Root.Free;
  end;
end;

// Removes the plugin-managed (and VS Code default-scaffold) delphi-win64 configs
// from a per-folder launch.json. In a multi-root workspace the .code-workspace
// "launch" section is authoritative and any per-folder config competes for F5.
// User-authored configs are preserved.
procedure CleanupPerFolderLaunchJson(const AProjectDir, AProjectName: string);
var
  LaunchFile: string;
  Root: TJSONObject;
  Configs: TJSONArray;

  function IsPluginOrScaffoldConfig(AItem: TJSONObject): Boolean;
  begin
    Result := False;
    if not SameText(AItem.GetValue<string>('type', ''), 'delphi-win64') then
      Exit;
    var ManagedVal := AItem.GetValue(PLUGIN_MANAGED_BY_FIELD);
    if (ManagedVal <> nil) and SameText(ManagedVal.Value, PLUGIN_MANAGED_BY_VALUE) then
      Exit(True);
    // Name fallback for entries written before the managedBy marker existed.
    // "Attach to <Project>.exe" only covers a program project; for a package the
    // attach entry is named after the Host application, which is not known here
    // -- but every attach entry the plugin has ever written carries managedBy,
    // so the check above already caught it.
    var ConfigName := AItem.GetValue<string>('name', '');
    for var Candidate in ['Debug Delphi Win64', 'Debug ' + AProjectName,
                          'Debug ' + AProjectName + ' (BPL)', 'Attach to ' + AProjectName + '.exe'] do
      if SameText(ConfigName, Candidate) then
        Exit(True);
  end;

begin
  LaunchFile := IncludeTrailingPathDelimiter(AProjectDir) + '.vscode\launch.json';
  if not TFile.Exists(LaunchFile) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(LaunchFile)) as TJSONObject;
  if Root = nil then
    Exit;
  try
    Configs := Root.GetValue('configurations') as TJSONArray;
    if Configs = nil then
      Exit;
    for var i := Configs.Count - 1 downto 0 do begin
      var Item := Configs.Items[i] as TJSONObject;
      if (Item <> nil) and IsPluginOrScaffoldConfig(Item) then
        Configs.Remove(i).Free;
    end;
    if Configs.Count = 0 then begin
      // No remaining configs -> delete the file so VS Code does not surface an
      // empty per-folder launch entry in the F5 dropdown.
      TFile.Delete(LaunchFile);
      Exit; // finally frees Root
    end;
    WriteTextIfChanged(LaunchFile, Root.Format, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

procedure GenerateOrUpdateTasksJsonInDir(const AProjectDir, AProjectName, AProjectFileName: string;
  AIsBpl, AIsDefault: Boolean);
var
  VscodePath, TasksFile: string;
  Root: TJSONObject;
  Tasks: TJSONArray;
begin
  VscodePath := IncludeTrailingPathDelimiter(AProjectDir) + '.vscode';
  if not TDirectory.Exists(VscodePath) then
    TDirectory.CreateDirectory(VscodePath);
  TasksFile := VscodePath + '\tasks.json';

  if TFile.Exists(TasksFile) then
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(TasksFile)) as TJSONObject
  else
    Root := nil;
  if Root = nil then begin
    Root := TJSONObject.Create;
    Root.AddPair('version', '2.0.0');
  end;
  try
    Tasks := Root.GetValue('tasks') as TJSONArray;
    if Tasks = nil then begin
      Tasks := TJSONArray.Create;
      Root.AddPair('tasks', Tasks);
    end;
    UpsertTaskConfig(Tasks, BuildBuildTaskConfig(AProjectName, AProjectFileName, AIsBpl), AIsDefault);
    WriteTextIfChanged(TasksFile, Root.Format, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

// Writes the .code-workspace "launch" (the managed configurations for the Delphi
// active project: launch first, so F5 starts it without a picker, then the
// matching attach entry) and "tasks" (one build task per project) sections.
// User-authored entries are preserved.
// Declared here because the implementation sits further down, next to the other
// workspace-folder helpers.
function ResolveFolderAbsPath(const ARelPath, AGroupPath: string): string; forward;

procedure UpdateWorkspaceDebuggerSections(Root: TJSONObject; Group: IOTAProjectGroup;
  const AGroupPath: string; ActiveProject: IOTAProject);
begin
  var LaunchSection := Root.GetValue('launch') as TJSONObject;
  if LaunchSection = nil then begin
    LaunchSection := TJSONObject.Create;
    Root.AddPair('launch', LaunchSection);
  end;
  if LaunchSection.GetValue('version') = nil then
    LaunchSection.AddPair('version', '0.2.0');
  var LaunchConfigs := LaunchSection.GetValue('configurations') as TJSONArray;
  if LaunchConfigs = nil then begin
    LaunchConfigs := TJSONArray.Create;
    LaunchSection.AddPair('configurations', LaunchConfigs);
  end;
  if ActiveProject <> nil then begin
    var AProjName := ChangeFileExt(ExtractFileName(ActiveProject.FileName), '');
    var AProjDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ActiveProject.FileName));
    var LaunchConfig: TJSONObject := nil;
    if TFile.Exists(ChangeFileExt(ActiveProject.FileName, '.dpr')) then
      LaunchConfig := BuildProgramLaunchConfig(AProjName, '', AProjDir, ActiveProject)
    else if TFile.Exists(ChangeFileExt(ActiveProject.FileName, '.dpk')) then begin
      var AHostApp := GetProjectHostApplication(ActiveProject);
      if AHostApp <> '' then
        LaunchConfig := BuildPackageLaunchConfig(AProjName, AProjDir, AHostApp, '',
          ActiveProject, ExcludeTrailingPathDelimiter(AGroupPath));
    end;
    if LaunchConfig <> nil then begin
      // ${workspaceFolder} is unambiguous only when the workspace has a single
      // root. With several roots VS Code requires the named form
      // ${workspaceFolder:Name}, so there the paths are left absolute.
      var PortabilityRoot := '';
      var Folders := Root.GetValue('folders') as TJSONArray;
      if (Folders <> nil) and (Folders.Count = 1) then begin
        var SingleRoot := (Folders.Items[0] as TJSONObject).GetValue<string>('path', '.');
        PortabilityRoot := ResolveFolderAbsPath(SingleRoot, AGroupPath);
      end;
      UpsertManagedDebugConfigsFor(LaunchConfigs, LaunchConfig, PortabilityRoot);
    end;
  end;

  // "tasks" section: one build task per project (absolute cwd, no [folder] suffix).
  var TasksSection := Root.GetValue('tasks') as TJSONObject;
  if TasksSection = nil then begin
    TasksSection := TJSONObject.Create;
    Root.AddPair('tasks', TasksSection);
  end;
  if TasksSection.GetValue('version') = nil then
    TasksSection.AddPair('version', '2.0.0');
  var WorkspaceTasks := TasksSection.GetValue('tasks') as TJSONArray;
  if WorkspaceTasks = nil then begin
    WorkspaceTasks := TJSONArray.Create;
    TasksSection.AddPair('tasks', WorkspaceTasks);
  end;
  // Drop the legacy aggregate task written by older versions.
  for var wi := WorkspaceTasks.Count - 1 downto 0 do begin
    var WItem := WorkspaceTasks.Items[wi] as TJSONObject;
    if (WItem <> nil) and (WItem.GetValue<string>('label', '') = 'Build All (Debug Win64)') then begin
      WorkspaceTasks.Remove(wi).Free;
      Break;
    end;
  end;
  // isDefault only for the project active in Delphi: Ctrl+Shift+B runs it directly.
  var ActiveProjName := '';
  if ActiveProject <> nil then
    ActiveProjName := ChangeFileExt(ExtractFileName(ActiveProject.FileName), '');
  for var wi := 0 to Group.ProjectCount - 1 do begin
    var WProj := Group.Projects[wi];
    var WProjName := ChangeFileExt(ExtractFileName(WProj.FileName), '');
    var WIsBpl := TFile.Exists(ChangeFileExt(WProj.FileName, '.dpk')) and
                  not TFile.Exists(ChangeFileExt(WProj.FileName, '.dpr'));
    UpsertTaskConfig(WorkspaceTasks, BuildBuildTaskConfig(WProjName, WProj.FileName, WIsBpl),
      SameText(WProjName, ActiveProjName));
  end;
end;

// Resolves a workspace folder path (relative to the .groupproj, or already absolute for
// projects outside the group tree / on other drives) into its normalized native absolute
// path, without trailing separator. '.' means the group folder itself.
function ResolveFolderAbsPath(const ARelPath, AGroupPath: string): string;
begin
  if ARelPath = '.' then
    Exit(ExcludeTrailingPathDelimiter(AGroupPath));

  var Native := StringReplace(ARelPath, '/', PathDelim, [rfReplaceAll]);
  if not TPath.IsPathRooted(Native) then
    Native := TPath.Combine(AGroupPath, Native);
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Native));
end;

// True if AChildAbs is strictly nested under AParentAbs (native absolute paths).
// Different drive/root -> not contained (StartsWith fails), so cross-drive is safe.
function IsProperSubFolderAbs(const AChildAbs, AParentAbs: string): Boolean;
begin
  if SameText(AChildAbs, AParentAbs) then
    Exit(False);
  Result := AChildAbs.StartsWith(IncludeTrailingPathDelimiter(AParentAbs), True);
end;

// Drops folders that overlap others in the list: any folder nested under another one
// (keeping the container, so every source file stays covered by exactly one root) and
// duplicates pointing at the same folder. VS Code does not handle nested multi-root
// folders well: files would appear twice, confusing search and the file mention picker.
// Comparison is done on ABSOLUTE paths (internal scratch): the emitted list stays
// relative, and no assumption is made about where the projects live.
procedure RemoveOverlappingFolders(AFolders: TList<string>; const AGroupPath: string);
var
  Abs: TArray<string>;
begin
  SetLength(Abs, AFolders.Count);
  for var i := 0 to AFolders.Count - 1 do
    Abs[i] := ResolveFolderAbsPath(AFolders[i], AGroupPath);

  for var i := AFolders.Count - 1 downto 0 do
    for var j := 0 to AFolders.Count - 1 do begin
      if i = j then
        Continue;
      // drop i if nested under j, or if it is the same folder as j but at a higher
      // index (so exactly one copy survives)
      if IsProperSubFolderAbs(Abs[i], Abs[j]) or (SameText(Abs[i], Abs[j]) and (i > j)) then begin
        AFolders.Delete(i);
        Delete(Abs, i, 1);
        Break;
      end;
    end;
end;

function GenerateOrUpdateVSCodeWorkspace(Group: IOTAProjectGroup): string;
var
  GroupPath, WorkspaceFile: string;
  Folders: TList<string>;
  Root: TJSONObject;
  FoldersArray, OldFolders: TJSONArray;
begin
  WorkspaceFile := ChangeFileExt(Group.FileName, '.code-workspace');
  GroupPath := IncludeTrailingPathDelimiter(ExtractFilePath(Group.FileName));

  Folders := TList<string>.Create;
  try
    for var i := 0 to Group.ProjectCount - 1 do begin
      var Proj := Group.Projects[i];
      var ProjFolder := IncludeTrailingPathDelimiter(ExtractFilePath(Proj.FileName));
      var RelPath := ExcludeTrailingPathDelimiter(
                       ExtractRelativePath(GroupPath, ProjFolder));
      if RelPath = '' then RelPath := '.';
      RelPath := StringReplace(RelPath, '\', '/', [rfReplaceAll]);
      if not Folders.Contains(RelPath) then
        Folders.Add(RelPath);
      // In workspace mode the .code-workspace "launch"/"tasks" sections are authoritative.
      // Remove competing per-folder launch.json/tasks.json plugin entries.
      if TPluginSettings.GenerateDebuggerConfig then begin
        var ProjDir := ExcludeTrailingPathDelimiter(ProjFolder);
        var ProjName := ChangeFileExt(ExtractFileName(Proj.FileName), '');
        if TFile.Exists(ChangeFileExt(Proj.FileName, '.dpr')) then begin
          CleanupPerFolderLaunchJson(ProjDir, ProjName);
          CleanupPerFolderTasksJson(ProjDir, ProjName, False);
        end else if TFile.Exists(ChangeFileExt(Proj.FileName, '.dpk')) then begin
          CleanupPerFolderLaunchJson(ProjDir, ProjName);
          CleanupPerFolderTasksJson(ProjDir, ProjName, True);
        end;
      end;
    end;

    // Avoid overlapping roots in the workspace: if a project sits in a subfolder of
    // another (or in the same folder as another), keep only the containing one.
    RemoveOverlappingFolders(Folders, GroupPath);

    if TFile.Exists(WorkspaceFile) then
      Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(WorkspaceFile)) as TJSONObject
    else
      Root := nil;
    if Root = nil then
      Root := TJSONObject.Create;

    try
      OldFolders := Root.GetValue('folders') as TJSONArray;

      FoldersArray := TJSONArray.Create;
      var ExistingPaths := TList<string>.Create;
      try
        if OldFolders <> nil then
          for var j := 0 to OldFolders.Count - 1 do begin
            var OldEntry := OldFolders.Items[j] as TJSONObject;
            if OldEntry = nil then
              continue;

            var ManagedByVal := OldEntry.GetValue(PLUGIN_MANAGED_BY_FIELD);
            var IsPluginManaged := (ManagedByVal <> nil) and
                                   SameText(ManagedByVal.Value, PLUGIN_MANAGED_BY_VALUE);
            if IsPluginManaged then
              continue;

            FoldersArray.AddElement(OldEntry.Clone as TJSONValue);

            var OldPathVal := OldEntry.GetValue('path');
            if (OldPathVal <> nil) and not ExistingPaths.Contains(OldPathVal.Value) then
              ExistingPaths.Add(OldPathVal.Value);
          end;

        for var RelPath in Folders do begin
          if ExistingPaths.Contains(RelPath) then
            continue;

          var FolderObj := TJSONObject.Create;

          // Preserve the previous name for this path (if any), even when rebuilding
          // plugin-managed entries.
          if OldFolders <> nil then
            for var j := 0 to OldFolders.Count - 1 do begin
              var OldEntry := OldFolders.Items[j] as TJSONObject;
              if OldEntry = nil then
                continue;
              var OldPathVal := OldEntry.GetValue('path');
              if (OldPathVal <> nil) and (OldPathVal.Value = RelPath) then begin
                var NameVal := OldEntry.GetValue('name');
                if NameVal <> nil then
                  FolderObj.AddPair('name', NameVal.Clone as TJSONValue);
                Break;
              end;
            end;

          FolderObj.AddPair('path', RelPath);
          FolderObj.AddPair(PLUGIN_MANAGED_BY_FIELD, PLUGIN_MANAGED_BY_VALUE);
          FoldersArray.AddElement(FolderObj);
        end;
      finally
        ExistingPaths.Free;
      end;

      Root.RemovePair('folders').Free;
      Root.AddPair('folders', FoldersArray);

      var Settings := Root.GetValue('settings') as TJSONObject;
      if Settings = nil then begin
        Settings := TJSONObject.Create;
        Root.AddPair('settings', Settings);
      end;
      var ActiveProject := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
      // Shared settings and recommendations come from the versioned defaults
      // file next to the .groupproj, created from the built-in defaults when it
      // does not exist yet.
      var SharedDefaults := LoadOrCreateWorkspaceDefaults(GroupPath);
      try
        try
          ApplyStandardDelphiSettings(Settings, ActiveProject, SharedDefaults);
        except
          on E: Exception do
            ShowMessage('Error updating settings: ' + E.ClassName + ': ' + E.Message);
        end;

        var ExtObj := Root.GetValue('extensions') as TJSONObject;
        if ExtObj = nil then begin
          ExtObj := TJSONObject.Create;
          Root.AddPair('extensions', ExtObj);
        end;
        MergeExtensionRecommendations(ExtObj, SharedDefaults);
      finally
        SharedDefaults.Free;
      end;

      if TPluginSettings.GenerateDebuggerConfig then
        UpdateWorkspaceDebuggerSections(Root, Group, GroupPath, ActiveProject);

      WriteTextIfChanged(WorkspaceFile, Root.Format, TEncoding.UTF8);
    finally
      Root.Free;
    end;
  finally
    Folders.Free;
  end;

  Result := WorkspaceFile;
end;

type
  TEditorWindowSearchData = record
    SearchTitle: string;
    WindowClassName: string;
    WindowTitleSuffix: string;
    FoundWindow: HWND;
  end;
  PEditorWindowSearchData = ^TEditorWindowSearchData;

function EditorEnumWindowsCallback(Wnd: HWND; LParam: LPARAM): BOOL; stdcall;
var
  Data: PEditorWindowSearchData;
  ClassName: array[0..127] of Char;
  Title: array[0..1023] of Char;
  TitleStr: string;
begin
  Result := True;
  if not IsWindowVisible(Wnd) then
    Exit;
  // GetClassName is very fast (kernel data, no IPC):
  // immediately discard anything that is not Electron/Chromium before touching GetWindowText
  GetClassName(Wnd, ClassName, Length(ClassName));
  Data := PEditorWindowSearchData(LParam);
  if (Data.WindowClassName <> '') and (string(ClassName) <> Data.WindowClassName) then
    Exit;
  GetWindowText(Wnd, Title, Length(Title));
  TitleStr := string(Title);
  if Pos(Data.SearchTitle, TitleStr) = 0 then
    Exit;
  if (Data.WindowTitleSuffix <> '') and (Pos(Data.WindowTitleSuffix, TitleStr) = 0) then
    Exit;
  Data.FoundWindow := Wnd;
  Result := False; // found, stop enumeration
end;

// Searches for an editor window that already has the indicated workspace open,
// based on the workspace name in the window title.
// Example titles:
//   "WorkspaceName (Workspace) — Visual Studio Code"
//   "FolderName — Cursor"
function FindEditorWindow(const WorkspacePath, WindowClassName, WindowTitleSuffix: string): HWND;
var
  WorkspaceName: string;
  Data: TEditorWindowSearchData;
begin
  if WorkspacePath.EndsWith('.code-workspace', True) then
    WorkspaceName := ChangeFileExt(ExtractFileName(WorkspacePath), '')
  else
    WorkspaceName := ExtractFileName(ExcludeTrailingPathDelimiter(WorkspacePath));

  Data.SearchTitle := WorkspaceName;
  Data.WindowClassName := WindowClassName;
  Data.WindowTitleSuffix := WindowTitleSuffix;
  Data.FoundWindow := 0;
  EnumWindows(@EditorEnumWindowsCallback, LPARAM(@Data));
  Result := Data.FoundWindow;
end;

type
  TChildFormInfo = record
    Module: IOTAModule;
    FormClassName: string;
  end;

function GetModuleFormEditor(Module: IOTAModule): IOTAFormEditor;
begin
  Result := nil;
  for var i := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[i], IOTAFormEditor, Result) then
      Exit;
end;

// Searches open modules for forms that inherit (directly or transitively) from
// ParentClassName. Uses RTTI via INTAComponent: no file parsing, works on
// compiled types in memory.
function FindOpenChildForms(ParentModule: IOTAModule; const ParentClassName: string): TArray<TChildFormInfo>;
var
  Results: TList<TChildFormInfo>;
  ModuleServices: IOTAModuleServices;
begin
  Results := TList<TChildFormInfo>.Create;
  try
    ModuleServices := BorlandIDEServices as IOTAModuleServices;
    for var i := 0 to ModuleServices.ModuleCount - 1 do begin
      var Module := ModuleServices.Modules[i];
      if Module = ParentModule then Continue;
      var FormEditor := GetModuleFormEditor(Module);
      if FormEditor = nil then Continue;
      var RootComp := FormEditor.GetRootComponent;
      if RootComp = nil then Continue;
      // INTAComponent exposes the real TComponent: use ClassType.ClassParent to
      // walk the inheritance chain without touching disk
      var NTAComp: INTAComponent;
      if not Supports(RootComp, INTAComponent, NTAComp) then Continue;
      var Comp := NTAComp.GetComponent;
      if Comp = nil then Continue;
      var AncestorClass := Comp.ClassType.ClassParent;
      var isDescendant := False;
      while AncestorClass <> nil do begin
        if AncestorClass.ClassName = ParentClassName then begin
          isDescendant := True;
          Break;
        end;
        AncestorClass := AncestorClass.ClassParent;
      end;
      if not isDescendant then Continue;
      var Info: TChildFormInfo;
      Info.Module := Module;
      Info.FormClassName := Comp.ClassName;
      Results.Add(Info);
    end;
    Result := Results.ToArray;
  finally
    Results.Free;
  end;
end;

// Returns False if the user cancelled.
// If the user chooses to close the children, closes them before returning True.
function CheckAndHandleChildForms(CurrentModule: IOTAModule): Boolean;
var
  FormEditor: IOTAFormEditor;
  RootComp: IOTAComponent;
  ParentClassName: string;
  Children: TArray<TChildFormInfo>;
begin
  Result := True;

  FormEditor := GetModuleFormEditor(CurrentModule);
  if FormEditor = nil then
    Exit;
  RootComp := FormEditor.GetRootComponent;
  if RootComp = nil then
    Exit;
  // GetComponentType can crash if the form designer is not open: use INTAComponent
  var NTARootComp: INTAComponent;
  if not Supports(RootComp, INTAComponent, NTARootComp) then
    Exit;
  var RootTComp := NTARootComp.GetComponent;
  if RootTComp = nil then
    Exit;
  ParentClassName := RootTComp.ClassName;
  if ParentClassName = '' then
    Exit;

  Children := FindOpenChildForms(CurrentModule, ParentClassName);
  if Length(Children) = 0 then
    Exit;

  var ChildList := '';
  for var Child in Children do
    ChildList := ChildList + '    • ' + Child.FormClassName + sLineBreak;

  var Dialog := TTaskDialog.Create(nil);
  try
    Dialog.Caption := 'Child forms open';
    Dialog.Title := 'Warning: child forms are open in the IDE';
    Dialog.Text :=
      'The following child forms of ' + ParentClassName + ' are open in the editor:' + sLineBreak + sLineBreak +
      ChildList + sLineBreak +
      'Delphi will not re-read changes made in Visual Studio Code while these forms remain open in the IDE.';
    Dialog.MainIcon := tdiWarning;
    Dialog.CommonButtons := [];
    Dialog.Flags := [tfUseCommandLinks];

    var BtnClose := Dialog.Buttons.Add;
    BtnClose.Caption := 'Close child forms automatically and proceed';
    BtnClose.ModalResult := 100;

    var BtnProceed := Dialog.Buttons.Add;
    BtnProceed.Caption := 'Proceed anyway' + #10 + 'I am aware that Delphi will not re-read the changes';
    BtnProceed.ModalResult := 101;

    var BtnCancel := Dialog.Buttons.Add;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.ModalResult := mrCancel;

    if not Dialog.Execute then begin
      Result := False;
      Exit;
    end;

    case Dialog.ModalResult of
      100: begin
        for var Child in Children do
          Child.Module.CloseModule(False);
      end;
      101: ; // proceed anyway
    else
      Result := False;
    end;
  finally
    Dialog.Free;
  end;
end;

function GetEffectiveEditorCommand(EditorSettings: TEditorSettings): string;
begin
  if EditorSettings = nil then
    Exit;

  Result := Trim(EditorSettings.Command);
  if Result <> '' then
    Exit;

  var DefaultSettings := TPluginSettings.CreateDefaultBuiltInEditorCopy(EditorSettings.Id);
  try
    if DefaultSettings <> nil then
      Result := DefaultSettings.Command;
  finally
    DefaultSettings.Free;
  end;

  if Result = '' then
    Exit;
end;

function QuoteCommandArgument(const Value: string): string;
begin
  if Value = '' then
  begin
    Result := '""';
    Exit;
  end;

  if Pos(' ', Value) > 0 then
  begin
    Result := '"' + Value + '"';
    Exit;
  end;

  Result := Value;
end;

function ExpandEditorArgumentTemplate(const Template, WorkspacePath, FileName: string;
  Line, Column: Integer): string;
begin
  Result := Template;
  Result := StringReplace(Result, '{workspacePath}', QuoteCommandArgument(WorkspacePath), [rfReplaceAll]);
  Result := StringReplace(Result, '{filePath}', QuoteCommandArgument(FileName), [rfReplaceAll]);
  Result := StringReplace(Result, '{line}', IntToStr(Line), [rfReplaceAll]);
  Result := StringReplace(Result, '{column}', IntToStr(Column), [rfReplaceAll]);

  var GotoTarget := QuoteCommandArgument(FileName + ':' + IntToStr(Line) + ':' + IntToStr(Column));
  Result := StringReplace(Result, '{gotoTarget}', GotoTarget, [rfReplaceAll]);
end;

function AppendArgumentBlock(const BaseArgs, ExtraArgs: string): string;
begin
  Result := Trim(BaseArgs);
  var TrimmedExtraArgs := Trim(ExtraArgs);
  if TrimmedExtraArgs = '' then
    Exit;

  if Result <> '' then
    Result := Result + ' ';
  Result := Result + TrimmedExtraArgs;
end;

function ResolveEditorLaunchArgs(EditorSettings: TEditorSettings; ReuseWindow: Boolean;
  WorkspacePath, FileName: string; Line, Column: Integer; HasDelphiLsp: Boolean): string;
begin
  if ReuseWindow then begin
    if Line < 0 then
      Result := ExpandEditorArgumentTemplate(EditorSettings.ReuseOpenArgs, WorkspacePath, FileName, Line, Column)
    else
      Result := ExpandEditorArgumentTemplate(EditorSettings.ReuseGotoArgs, WorkspacePath, FileName, Line, Column);
  end else begin
    if Line < 0 then
      Result := ExpandEditorArgumentTemplate(EditorSettings.NewOpenArgs, WorkspacePath, FileName, Line, Column)
    else
      Result := ExpandEditorArgumentTemplate(EditorSettings.NewGotoArgs, WorkspacePath, FileName, Line, Column);
  end;

  if HasDelphiLsp then
    Result := AppendArgumentBlock(Result, EditorSettings.DelphiLspArgs);
end;

// Returns the configured editor executable, quoted only if the path contains spaces,
// for safe embedding inside cmd /c "...".
// Strips any user-supplied surrounding quotes before deciding.
function QuotedEditorCommand(const EditorCommand: string): string;
var
  cmd: string;
begin
  cmd := Trim(EditorCommand);
  if cmd = '' then
    Exit;
  if (Length(cmd) >= 2) and (cmd[1] = '"') and (cmd[Length(cmd)] = '"') then
    cmd := Copy(cmd, 2, Length(cmd) - 2);
  if Pos(' ', cmd) > 0 then
    Result := '"' + cmd + '"'
  else
    Result := cmd;
end;

procedure ShowEditorLaunchError(const EditorDisplayName, CmdLine, WorkDir, StdOutText,
  StdErrText, ErrorKind, ErrorMessage: string; ExitCode: DWORD);
begin
  var DisplayName := Trim(EditorDisplayName);
  if DisplayName = '' then
    DisplayName := 'External editor';

  var Details :=
    DisplayName + ' could not be started.' + sLineBreak + sLineBreak +
    'Error kind: ' + ErrorKind + sLineBreak +
    'Original message: ' + ErrorMessage + sLineBreak +
    'Command line: ' + CmdLine + sLineBreak +
    'Working directory: ' + WorkDir + sLineBreak +
    'Exit code: ' + IntToStr(ExitCode) + sLineBreak + sLineBreak +
    'STDOUT:' + sLineBreak + StdOutText + sLineBreak + sLineBreak +
    'STDERR:' + sLineBreak + StdErrText;

  TFrmVSCodeLaunchError.ShowDialog(
    'Error starting ' + DisplayName,
    'The plugin failed to launch ' + DisplayName + '. You can copy all details below.',
    Details);
end;

function TryGetActiveProjectSourceFile(out FileName: string): Boolean;
var
  Project: IOTAProject;
  Editor: IOTASourceEditor;
begin
  Result := False;
  FileName := '';
  Project := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
  if Project = nil then
    Exit;

  // First: try to find the .dpr/.dpk editor if it is already open in the IDE
  Editor := FindSourceEditor(Project, ['.DPR', '.DPK']);
  if Editor <> nil then begin
    FileName := Editor.FileName;
    Result := FileName <> '';
    Exit;
  end;

  // Fallback: derive the source filename from the .dproj path (the editor may not be open)
  for var Ext in ['.dpr', '.dpk'] do begin
    var Candidate := ChangeFileExt(Project.FileName, Ext);
    if TFile.Exists(Candidate) then begin
      FileName := Candidate;
      Result := True;
      Exit;
    end;
  end;
end;

procedure GenerateOrUpdateLaunchJson(const FolderPath: string; Project: IOTAProject);
begin
  if Project = nil then
    Exit;

  var ProjectDir := ExcludeTrailingPathDelimiter(FolderPath);
  var ProjectName := ChangeFileExt(ExtractFileName(Project.FileName), '');

  var Config: TJSONObject := nil;
  var IsBpl := False;
  if TFile.Exists(ChangeFileExt(Project.FileName, '.dpr')) then
    Config := BuildProgramLaunchConfig(ProjectName, '', ProjectDir, Project)
  else if TFile.Exists(ChangeFileExt(Project.FileName, '.dpk')) then begin
    IsBpl := True;
    var HostApp := GetProjectHostApplication(Project);
    if Trim(HostApp) = '' then begin
      ShowMessage('launch.json not updated: package "' + ProjectName +
        '" has no Host application configured (Project Options > Debugger > Host application).');
      Exit;
    end;
    Config := BuildPackageLaunchConfig(ProjectName, ProjectDir, HostApp, '', Project);
  end;
  if Config = nil then
    Exit;

  WriteManagedLaunchConfigToDir(ProjectDir, Config);
  GenerateOrUpdateTasksJsonInDir(ProjectDir, ProjectName, Project.FileName, IsBpl, True);
end;

procedure OpenCurrentFileInEditor(EditorSettings: TEditorSettings);
begin
  if EditorSettings = nil then begin
    ShowMessage('No editor configuration found');
    Exit;
  end;

  var sourceInfos: TCurrentSourceFileInfos;
  if not TryGetCurrentSourceFileInfos(sourceInfos) then begin
    var fallbackFile: string;
    if TryGetActiveProjectSourceFile(fallbackFile) then begin
      sourceInfos.FileName := fallbackFile;
      sourceInfos.Line := 1;  // force goto args so {gotoTarget}/{filePath} are passed to the editor
      sourceInfos.Column := 1;
    end else begin
      ShowMessage(
        'The active tab is not a Delphi source editor. ' +
        'Select a .pas/.dpr/.inc/.dpk/.dfm/.fmx file and try again.');
      Exit;
    end;
  end;

  var FileName := sourceInfos.FileName;

  var CurrentModule := (BorlandIDEServices as IOTAModuleServices).CurrentModule;
  if (CurrentModule <> nil) and not CheckAndHandleChildForms(CurrentModule) then
    Exit;

  if not SaveAllModules then
    exit;

  // Determine the workspace to open: use the project group's .code-workspace if available,
  // otherwise fall back to the active project's folder
  var WorkspacePath: string;
  var UsedGroupWorkspace := False;
  var Group := GetActiveProjectGroup;
  if (Group <> nil) and TFile.Exists(Group.FileName) then begin
    WorkspacePath := GenerateOrUpdateVSCodeWorkspace(Group);
    UsedGroupWorkspace := True;
  end
  else begin
    var project := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
    if project = nil then begin
      ShowMessage('No active project found');
      exit;
    end;
    WorkspacePath := ExtractFilePath(project.FileName);
    GenerateOrUpdateVSCodeFolderSettings(WorkspacePath, project);
  end;

  // Generate/update .vscode/launch.json + tasks.json for the delphi-win64 debugger,
  // ONLY in folder mode. In workspace mode these live in the .code-workspace
  // "launch"/"tasks" sections; a per-folder copy would compete with them for F5.
  if (not UsedGroupWorkspace) and TPluginSettings.GenerateDebuggerConfig then begin
    var VscodeFolderPath := ExcludeTrailingPathDelimiter(WorkspacePath);
    var LaunchProject := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
    if LaunchProject <> nil then
      try
        GenerateOrUpdateLaunchJson(VscodeFolderPath, LaunchProject);
      except
        on E: Exception do
          ShowMessage('launch.json generation failed: ' + E.ClassName + ': ' + E.Message);
      end
    else
      ShowMessage('launch.json: GetActiveProject returned nil');
  end;

  // Capture variables for the thread (ToolsAPI is not thread-safe, must only be used on the main thread)
  var WorkspacePathCapture := WorkspacePath;
  var FileNameCapture := FileName;
  var LineCapture := sourceInfos.Line;
  var ColCapture := sourceInfos.Column;
  var EditorDisplayNameCapture := Trim(EditorSettings.DisplayName);
  if EditorDisplayNameCapture = '' then
    EditorDisplayNameCapture := 'External editor';
  var EditorCommandCapture := GetEffectiveEditorCommand(EditorSettings);
  if EditorCommandCapture = '' then begin
    ShowMessage(
      'No executable is configured for ' + EditorDisplayNameCapture + '.' + sLineBreak + sLineBreak +
      'Open Tools > Options > Third Party > Edit in VS Code and use Advanced Settings to configure it.');
    Exit;
  end;
  var EditorWindowClassNameCapture := EditorSettings.WindowClassName;
  var EditorWindowTitleSuffixCapture := EditorSettings.WindowTitleSuffix;
  var EditorReuseOpenArgsCapture := EditorSettings.ReuseOpenArgs;
  var EditorReuseGotoArgsCapture := EditorSettings.ReuseGotoArgs;
  var EditorNewOpenArgsCapture := EditorSettings.NewOpenArgs;
  var EditorNewGotoArgsCapture := EditorSettings.NewGotoArgs;
  var EditorDelphiLspArgsCapture := EditorSettings.DelphiLspArgs;

  // Check if the active project has a .delphilsp.json: if so, add
  // --command delphilsp.selectSettingsFile to trigger LSP reload
  var HasDelphiLspCapture := False;
  var ActiveProj := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
  if ActiveProj <> nil then
    HasDelphiLspCapture := TFile.Exists(ChangeFileExt(ActiveProj.FileName, '.delphilsp.json'));

  // EnumWindows and Execute run in background to avoid blocking the IDE
  TThread.CreateAnonymousThread(procedure
  var
    EditorWindow: HWND;
    cmdline: string;
    quotedCmd: string;
    launchArgs: string;
    workDir: string;
    stdOutText: string;
    stdErrText: string;
    exitCode: DWORD;
    EditorLaunchSettings: TEditorSettings;
  begin
    try
      quotedCmd := QuotedEditorCommand(EditorCommandCapture);
      EditorLaunchSettings := TEditorSettings.Create(
        '', EditorDisplayNameCapture, '', True, EditorCommandCapture, 0,
        EditorWindowClassNameCapture, EditorWindowTitleSuffixCapture,
        EditorReuseOpenArgsCapture, EditorReuseGotoArgsCapture,
        EditorNewOpenArgsCapture, EditorNewGotoArgsCapture,
        EditorDelphiLspArgsCapture);
      try
      if Trim(EditorWindowTitleSuffixCapture) = '' then
        EditorWindow := 0
      else
        EditorWindow := FindEditorWindow(
          WorkspacePathCapture,
          EditorWindowClassNameCapture,
          EditorWindowTitleSuffixCapture);
      if EditorWindow <> 0 then begin
        // Matching editor window with this workspace already open: bring it to the front and reuse it
        SetForegroundWindow(EditorWindow);
        launchArgs := ResolveEditorLaunchArgs(
          EditorLaunchSettings,
          True,
          WorkspacePathCapture,
          FileNameCapture,
          LineCapture,
          ColCapture,
          HasDelphiLspCapture);
      end else begin
        // No matching editor window found for this workspace: open a new instance
        launchArgs := ResolveEditorLaunchArgs(
          EditorLaunchSettings,
          False,
          WorkspacePathCapture,
          FileNameCapture,
          LineCapture,
          ColCapture,
          HasDelphiLspCapture);
      end;
      finally
        EditorLaunchSettings.Free;
      end;

      cmdline := Format('cmd /c "%s %s"', [quotedCmd, launchArgs]);

      workDir := ExtractFilePath(FileNameCapture);
      stdOutText := '';
      stdErrText := '';

      var executor := TOSCommandLineExecutor.Create(nil);
      var OnStdErr: TOSCommandLineExecutor.TLogProc;
      var OnStdOut: TOSCommandLineExecutor.TLogProc;
      try
        executor.WorkDir := workDir;
        executor.CmdLine := cmdline;
        OnStdErr :=
          procedure(txt: string)
          begin
            if stdErrText <> '' then
              stdErrText := stdErrText + sLineBreak;
            stdErrText := stdErrText + txt;
          end;
        OnStdOut :=
          procedure(txt: string)
          begin
            if stdOutText <> '' then
              stdOutText := stdOutText + sLineBreak;
            stdOutText := stdOutText + txt;
          end;
        exitCode := executor.Execute(OnStdErr, OnStdOut);
      finally
        executor.Free;
      end;

      if exitCode <> 0 then
        TThread.Queue(nil,
          procedure
          begin
            ShowEditorLaunchError(
              EditorDisplayNameCapture,
              cmdline,
              workDir,
              stdOutText,
              stdErrText,
              'ProcessExitCode',
              'The editor command returned a non-zero exit code.',
              exitCode);
          end);
    except
      on E: Exception do
        TThread.Queue(nil,
          procedure
          begin
            ShowEditorLaunchError(
              EditorDisplayNameCapture,
              cmdline,
              workDir,
              stdOutText,
              stdErrText,
              E.ClassName,
              E.Message,
              DWORD($FFFFFFFF));
          end);
    end;
  end).Start;
end;

procedure OpenCurrentFileInVisualStudioCode;
begin
  OpenCurrentFileInEditor(TPluginSettings.BuiltInEditors[0]);
end;

function GetEnabledEditors: TArray<TEditorSettings>;
begin
  var EnabledEditors := TList<TEditorSettings>.Create;
  try
    for var Editor in TPluginSettings.BuiltInEditors do
      if Editor.Enabled then
        EnabledEditors.Add(Editor);

    for var Editor in TPluginSettings.CustomEditors do
      if Editor.Enabled then
        EnabledEditors.Add(Editor);

    Result := EnabledEditors.ToArray;
  finally
    EnabledEditors.Free;
  end;
end;

procedure OpenPluginOptionsPage;
begin
  var EnvironmentOptions: IOTAEnvironmentOptions;
  if Supports(BorlandIDEServices, IOTAEnvironmentOptions, EnvironmentOptions) then begin
    EnvironmentOptions.EditOptions('Third Party', 'Edit in VS Code');
    Exit;
  end;

  ShowMessage('Open Tools > Options > Third Party > Edit in VS Code to configure the plugin.');
end;


type
  TMenuHandler = class
  strict private
    Item: TMenuItem;
    EditorSettings: TEditorSettings;
    ExecuteProc: TProc;
    MenuAction: TAction;
    procedure OnExecute(Sender: TObject);
    constructor Create(aCaption: string; aAction: TProc; aShortcut: string);
    constructor CreateForEditor(aCaption: string; aEditorSettings: TEditorSettings; aShortcut: string);
  class var
    MenuHandlers: TObjectList<TMenuHandler>;
    FActionList: TActionList;
  public
    destructor Destroy; override;
    procedure UpdateShortcut(AShortCut: TShortCut);
    class constructor Create;
    class destructor Destroy;
    class procedure ClearMenuItems;
    class function AddMenuItem(NTAServices: INTAServices; aCaption: string; aAction: TProc; aShortcut: string = ''): TMenuHandler;
    class function AddEditorMenuItem(NTAServices: INTAServices; aCaption: string; aEditorSettings: TEditorSettings;
      aShortcut: string = ''): TMenuHandler;
  end;

  TMenuRegistrationHelper = class
    procedure OnTimer(Sender: TObject);
  end;

class constructor TMenuHandler.Create;
begin
  MenuHandlers := TObjectList<TMenuHandler>.Create;
  FActionList := TActionList.Create(nil);
end;

class destructor TMenuHandler.Destroy;
begin
  MenuHandlers.Free;
  FActionList.Free;
end;

constructor TMenuHandler.Create(aCaption: string; aAction: TProc; aShortcut: string);
begin
  inherited Create;
  ExecuteProc := aAction;
  MenuAction := TAction.Create(FActionList);
  MenuAction.Caption := aCaption;
  MenuAction.OnExecute := OnExecute;

  if aShortcut <> '' then
    MenuAction.ShortCut := TextToShortCut(aShortcut);

  Item := TMenuItem.Create(nil);
  Item.Action := MenuAction;
end;

constructor TMenuHandler.CreateForEditor(aCaption: string; aEditorSettings: TEditorSettings; aShortcut: string);
begin
  Create(aCaption, nil, aShortcut);
  EditorSettings := aEditorSettings;
end;

destructor TMenuHandler.Destroy;
begin
  FreeAndNil(Item);
  FreeAndNil(MenuAction);
  inherited;
end;

procedure TMenuHandler.OnExecute(Sender: TObject);
begin
  if EditorSettings <> nil then begin
    OpenCurrentFileInEditor(EditorSettings);
    Exit;
  end;

  if Assigned(ExecuteProc) then
    ExecuteProc;
end;

procedure TMenuHandler.UpdateShortcut(AShortCut: TShortCut);
begin
  (Item.Action as TAction).ShortCut := AShortCut;
end;

class function TMenuHandler.AddMenuItem(NTAServices: INTAServices; aCaption: string; aAction: TProc; aShortcut: string = ''): TMenuHandler;
begin
  Result := TMenuHandler.Create(aCaption, aAction, aShortcut);
  MenuHandlers.Add(Result);
  // Adding menu items to the top of the Tools menu because all
  // the menu items under "Configure Tools..." get deleted whenever you open its dialog.
  NTAServices.AddActionMenu('ToolsMenu', nil, Result.Item, False, True);
end;

class function TMenuHandler.AddEditorMenuItem(NTAServices: INTAServices; aCaption: string;
  aEditorSettings: TEditorSettings; aShortcut: string = ''): TMenuHandler;
begin
  Result := TMenuHandler.CreateForEditor(aCaption, aEditorSettings, aShortcut);
  MenuHandlers.Add(Result);
  NTAServices.AddActionMenu('ToolsMenu', nil, Result.Item, False, True);
end;

class procedure TMenuHandler.ClearMenuItems;
begin
  MenuHandlers.Clear;
end;

procedure TryRegisterMainMenuItems; forward;
procedure RebuildMainMenuItems; forward;

procedure TMenuRegistrationHelper.OnTimer(Sender: TObject);
begin
  TryRegisterMainMenuItems;
end;

var
  GOpenVSCodeHandler: TMenuHandler = nil;
  GSetupMenuHandler: TMenuHandler = nil;
  GRegisteredMenuCount: Integer = 0;
  GOptions: TEditInVSCodeOptions = nil;
  GMenuRegistrationTimer: TTimer = nil;
  GMenuRegistrationHelper: TMenuRegistrationHelper = nil;

procedure TryRegisterMainMenuItems;
var
  NTAServices: INTAServices;
begin
  if GRegisteredMenuCount > 0 then
    Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then
    Exit;
  if (NTAServices.MainMenu = nil) or (NTAServices.MainMenu.Items.Count = 0) then
    Exit;

  var EnabledEditors := GetEnabledEditors;
  if Length(EnabledEditors) = 0 then begin
    GSetupMenuHandler := TMenuHandler.AddMenuItem(
      NTAServices,
      PLUGIN_SETTINGS_MENU_CAPTION,
      OpenPluginOptionsPage);
    Inc(GRegisteredMenuCount);
    FreeAndNil(GMenuRegistrationTimer);
    Exit;
  end;

  for var Editor in EnabledEditors do begin
    var DisplayName := Trim(Editor.DisplayName);
    if DisplayName = '' then
      DisplayName := 'Custom Editor';

    var MenuHandler := TMenuHandler.AddEditorMenuItem(
      NTAServices,
      'Edit in ' + DisplayName,
      Editor,
      ShortCutToText(Editor.Shortcut));

    if SameText(Editor.Id, 'vscode') then
      GOpenVSCodeHandler := MenuHandler;

    Inc(GRegisteredMenuCount);
  end;

  FreeAndNil(GMenuRegistrationTimer);
end;

procedure RebuildMainMenuItems;
begin
  TMenuHandler.ClearMenuItems;
  GOpenVSCodeHandler := nil;
  GSetupMenuHandler := nil;
  GRegisteredMenuCount := 0;
  TryRegisterMainMenuItems;
end;

procedure UnregisterOptions;
var
  svc: INTAEnvironmentOptionsServices;
begin
  FreeAndNil(GMenuRegistrationTimer);
  FreeAndNil(GMenuRegistrationHelper);

  if GOptions = nil then
    Exit;
  if BorlandIDEServices = nil then
    Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, svc) then
    svc.UnregisterAddInOptions(GOptions);
  FreeAndNil(GOptions);
end;

procedure Register;
var
  OptionsServices: INTAEnvironmentOptionsServices;
begin
  TPluginSettings.Load;
  TPluginSettings.OnShortcutChanged :=
    procedure(sc: TShortCut)
    begin
      if GOpenVSCodeHandler <> nil then
        GOpenVSCodeHandler.UpdateShortcut(sc);
    end;
  TPluginSettings.OnSettingsChanged :=
    procedure
    begin
      RebuildMainMenuItems;
    end;

  GOptions := TEditInVSCodeOptions.Create;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, OptionsServices) then
    OptionsServices.RegisterAddInOptions(GOptions);

  TryRegisterMainMenuItems;
  if GRegisteredMenuCount = 0 then begin
    if GMenuRegistrationHelper = nil then
      GMenuRegistrationHelper := TMenuRegistrationHelper.Create;
    GMenuRegistrationTimer := TTimer.Create(nil);
    GMenuRegistrationTimer.Enabled := False;
    GMenuRegistrationTimer.Interval := 250;
    GMenuRegistrationTimer.OnTimer := GMenuRegistrationHelper.OnTimer;
    GMenuRegistrationTimer.Enabled := True;
  end;
end;
initialization
finalization
  UnregisterOptions;

end.

