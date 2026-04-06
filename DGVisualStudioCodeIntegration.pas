unit DGVisualStudioCodeIntegration;

interface

procedure Register;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.UITypes,
  System.Generics.Collections,
  ToolsAPI,
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

// Applies standard Delphi settings to a JSON object.
// Used both in .code-workspace (Settings is the "settings" sub-object)
// and in .vscode/settings.json (Settings is the file root).
procedure ApplyStandardDelphiSettings(Settings: TJSONObject; ActiveProject: IOTAProject);
  procedure AddIfMissing(Target: TJSONObject; const Key: string; Value: TJSONValue);
  begin
    if Target.GetValue(Key) = nil then
      Target.AddPair(Key, Value)
    else
      Value.Free;
  end;

  procedure AddTrueIfMissing(Target: TJSONObject; const Key: string);
  begin
    AddIfMissing(Target, Key, TJSONBool.Create(True));
  end;

begin
  // files.exclude: preserve user values and only add missing defaults
  var FilesExclude := Settings.GetValue('files.exclude') as TJSONObject;
  if FilesExclude = nil then begin
    FilesExclude := TJSONObject.Create;
    Settings.AddPair('files.exclude', FilesExclude);
  end;
  for var Pattern in ['**/Debug', '**/Release',
                      '**/Win32/Debug', '**/Win32/Release',
                      '**/Win64/Debug', '**/Win64/Release',
                      '**/__recovery', '**/__history',
                      '**/.#*', '**/*.rc', '**/*.res', '**/*.RES',
                      '**/*.bak', '**/*.BAK'] do
    AddTrueIfMissing(FilesExclude, Pattern);

  AddIfMissing(Settings, 'files.trimTrailingWhitespace', TJSONBool.Create(True));
  AddIfMissing(Settings, 'files.autoGuessEncoding', TJSONBool.Create(True));
  AddIfMissing(Settings, 'editor.detectIndentation', TJSONBool.Create(False));
  AddIfMissing(Settings, 'editor.foldingMaximumRegions', TJSONNumber.Create(8000));

  // [objectpascal]: bracket pairs for begin/end, case/end, etc.
  var PascalSettings := Settings.GetValue('[objectpascal]') as TJSONObject;
  if PascalSettings = nil then begin
    PascalSettings := TJSONObject.Create;
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
  end;

  // [markdown]: preserve trailing whitespace
  var MarkdownSettings := Settings.GetValue('[markdown]') as TJSONObject;
  if MarkdownSettings = nil then begin
    MarkdownSettings := TJSONObject.Create;
    Settings.AddPair('[markdown]', MarkdownSettings);
  end;
  AddIfMissing(MarkdownSettings, 'files.trimTrailingWhitespace', TJSONBool.Create(False));
  AddIfMissing(MarkdownSettings, 'editor.trimAutoWhitespace', TJSONBool.Create(False));

  // delphiLsp.settingsFile: point to the active project's .delphilsp.json
  if ActiveProject <> nil then begin
    var DelphiLspFile := ChangeFileExt(ActiveProject.FileName, '.delphilsp.json');
    if TFile.Exists(DelphiLspFile) then
      AddIfMissing(Settings, 'delphiLsp.settingsFile', TJSONString.Create(PathToFileUri(DelphiLspFile)));
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

procedure MergeExtensionRecommendations(ExtensionsObject: TJSONObject);
var
  ExistingRecommendations: TJSONArray;
  DefaultRecommendations: TJSONArray;
  HasItem: Boolean;
begin
  ExistingRecommendations := ExtensionsObject.GetValue('recommendations') as TJSONArray;
  if ExistingRecommendations = nil then begin
    ExtensionsObject.AddPair('recommendations', BuildExtensionRecommendations);
    Exit;
  end;

  DefaultRecommendations := BuildExtensionRecommendations;
  try
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
    DefaultRecommendations.Free;
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
  try
    ApplyStandardDelphiSettings(Root, ActiveProject);
    TFile.WriteAllText(SettingsFile, Root.Format, TEncoding.UTF8);
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
    MergeExtensionRecommendations(ExtRoot);
    TFile.WriteAllText(ExtFile, ExtRoot.Format, TEncoding.UTF8);
  finally
    ExtRoot.Free;
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
      var ProjFolder := IncludeTrailingPathDelimiter(
                          ExtractFilePath(Group.Projects[i].FileName));
      var RelPath := ExcludeTrailingPathDelimiter(
                       ExtractRelativePath(GroupPath, ProjFolder));
      if RelPath = '' then RelPath := '.';
      RelPath := StringReplace(RelPath, '\', '/', [rfReplaceAll]);
      if not Folders.Contains(RelPath) then
        Folders.Add(RelPath);
    end;

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
      try
        ApplyStandardDelphiSettings(Settings, ActiveProject);
      except
        on E: Exception do
          ShowMessage('Error updating settings: ' + E.ClassName + ': ' + E.Message);
      end;

      var ExtObj := Root.GetValue('extensions') as TJSONObject;
      if ExtObj = nil then begin
        ExtObj := TJSONObject.Create;
        Root.AddPair('extensions', ExtObj);
      end;
      MergeExtensionRecommendations(ExtObj);

      TFile.WriteAllText(WorkspaceFile, Root.Format, TEncoding.UTF8);
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
  var Group := GetActiveProjectGroup;
  if (Group <> nil) and TFile.Exists(Group.FileName) then
    WorkspacePath := GenerateOrUpdateVSCodeWorkspace(Group)
  else begin
    var project := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
    if project = nil then begin
      ShowMessage('No active project found');
      exit;
    end;
    WorkspacePath := ExtractFilePath(project.FileName);
    GenerateOrUpdateVSCodeFolderSettings(WorkspacePath, project);
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

