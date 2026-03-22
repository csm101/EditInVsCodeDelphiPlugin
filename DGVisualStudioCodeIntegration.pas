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
  Winapi.Windows,
  WinApi.ShellAPI;


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
    exit(Module.Save(False, True));
  end;
  exit(true);
end;

function SaveAllModules: boolean;
var
  Services: IOTAModuleServices;
  I: Integer;
  Module: IOTAModule;
begin
  result := false;
  Services := BorlandIDEServices as IOTAModuleServices;
  for I := 0 to Services.ModuleCount - 1 do begin
    Module := Services.Modules[I];
    if not SaveModule(Module) then
      exit;
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
        exit;
  end;

  Result := nil;
end;

type
  TCurrentSourceFileInfos = record
    FileName: string;
    Line: Integer;
    Column: Integer;
  end;

function GetCurrentSourceFileInfos: TCurrentSourceFileInfos;
var
  EditView: IOTAEditView;
begin
  var Services := BorlandIDEServices as IOTAModuleServices;

  var Module := Services.CurrentModule;
  if Module = nil then
    raise Exception.Create('Current module not found');

  var editor := FindSourceEditor(Module, ['.PAS', '.DPR', '.INC', '.DPK', '.DFM', '.FMX']);

  if editor = nil then
    raise Exception.Create(
      'The active tab is not a Delphi source editor. ' +
      'Select a .pas/.dpr/.inc/.dpk/.dfm/.fmx file and try again.');
  if editor.EditViewCount = 0 then
    raise Exception.Create(
      'The source editor is not visible. ' +
      'Open the code editor tab and try again.');

  Result.FileName := editor.FileName;
  result.Line := -1;
  result.Column := -1;

  EditView := editor.GetEditView(0);
  if EditView <> nil then begin
    Result.Line := EditView.CursorPos.Line;
    Result.Column := EditView.CursorPos.Col;
  end
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
  TVSCodeSearchData = record
    SearchTitle: string;
    FoundWindow: HWND;
  end;
  PVSCodeSearchData = ^TVSCodeSearchData;

function VSCodeEnumWindowsCallback(Wnd: HWND; LParam: LPARAM): BOOL; stdcall;
var
  Data: PVSCodeSearchData;
  ClassName: array[0..127] of Char;
  Title: array[0..1023] of Char;
  TitleStr: string;
begin
  Result := True;
  if not IsWindowVisible(Wnd) then Exit;
  // GetClassName is very fast (kernel data, no IPC):
  // immediately discard anything that is not Electron/Chromium before touching GetWindowText
  GetClassName(Wnd, ClassName, Length(ClassName));
  if string(ClassName) <> 'Chrome_WidgetWin_1' then Exit;
  Data := PVSCodeSearchData(LParam);
  GetWindowText(Wnd, Title, Length(Title));
  TitleStr := string(Title);
  if (Pos(Data.SearchTitle, TitleStr) > 0) and
     (Pos('Visual Studio Code', TitleStr) > 0) then begin
    Data.FoundWindow := Wnd;
    Result := False; // found, stop enumeration
  end;
end;

// Searches for a VSCode window that already has the indicated workspace open,
// based on the workspace name in the window title.
// Expected title: "WorkspaceName (Workspace) — Visual Studio Code"
//             or: "FolderName — Visual Studio Code"
function FindVSCodeWindow(const WorkspacePath: string): HWND;
var
  WorkspaceName: string;
  Data: TVSCodeSearchData;
begin
  if WorkspacePath.EndsWith('.code-workspace', True) then
    WorkspaceName := ChangeFileExt(ExtractFileName(WorkspacePath), '')
  else
    WorkspaceName := ExtractFileName(ExcludeTrailingPathDelimiter(WorkspacePath));

  Data.SearchTitle := WorkspaceName;
  Data.FoundWindow := 0;
  EnumWindows(@VSCodeEnumWindowsCallback, LPARAM(@Data));
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
  if FormEditor = nil then Exit;
  RootComp := FormEditor.GetRootComponent;
  if RootComp = nil then Exit;
  // GetComponentType can crash if the form designer is not open: use INTAComponent
  var NTARootComp: INTAComponent;
  if not Supports(RootComp, INTAComponent, NTARootComp) then Exit;
  var RootTComp := NTARootComp.GetComponent;
  if RootTComp = nil then Exit;
  ParentClassName := RootTComp.ClassName;
  if ParentClassName = '' then Exit;

  Children := FindOpenChildForms(CurrentModule, ParentClassName);
  if Length(Children) = 0 then Exit;

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

// Returns the configured VS Code executable, quoted only if the path contains spaces,
// for safe embedding inside cmd /c "...".
// Strips any user-supplied surrounding quotes before deciding.
function QuotedVSCodeCommand: string;
var
  cmd: string;
begin
  cmd := Trim(TPluginSettings.VSCodeCommand);
  if cmd = '' then
    cmd := DEFAULT_VSCODE_COMMAND;
  if (Length(cmd) >= 2) and (cmd[1] = '"') and (cmd[Length(cmd)] = '"') then
    cmd := Copy(cmd, 2, Length(cmd) - 2);
  if Pos(' ', cmd) > 0 then
    Result := '"' + cmd + '"'
  else
    Result := cmd;
end;

procedure ShowVSCodeLaunchError(const CmdLine, WorkDir, StdOutText, StdErrText,
  ErrorKind, ErrorMessage: string; ExitCode: DWORD);
begin
  var Details :=
    'Visual Studio Code could not be started.' + sLineBreak + sLineBreak +
    'Error kind: ' + ErrorKind + sLineBreak +
    'Original message: ' + ErrorMessage + sLineBreak +
    'Command line: ' + CmdLine + sLineBreak +
    'Working directory: ' + WorkDir + sLineBreak +
    'Exit code: ' + IntToStr(ExitCode) + sLineBreak + sLineBreak +
    'STDOUT:' + sLineBreak + StdOutText + sLineBreak + sLineBreak +
    'STDERR:' + sLineBreak + StdErrText;

  TFrmVSCodeLaunchError.ShowDialog(
    'Error starting Visual Studio Code',
    'The plugin failed to launch Visual Studio Code. You can copy all details below.',
    Details);
end;

procedure OpenCurrentFileInVisualStudioCode;
begin
  var sourceInfos: TCurrentSourceFileInfos;
  try
    sourceInfos := GetCurrentSourceFileInfos;
  except
    on E: Exception do begin
      ShowMessage(E.Message);
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

  // Check if the active project has a .delphilsp.json: if so, add
  // --command delphilsp.selectSettingsFile to trigger LSP reload
  var HasDelphiLspCapture := False;
  var ActiveProj := (BorlandIDEServices as IOTAModuleServices).GetActiveProject;
  if ActiveProj <> nil then
    HasDelphiLspCapture := TFile.Exists(ChangeFileExt(ActiveProj.FileName, '.delphilsp.json'));

  // EnumWindows and Execute run in background to avoid blocking the IDE
  TThread.CreateAnonymousThread(procedure
  var
    VSCodeWindow: HWND;
    cmdline: string;
    quotedCmd: string;
    DelphiLspCmd: string;
    workDir: string;
    stdOutText: string;
    stdErrText: string;
    exitCode: DWORD;
  begin
    try
      if HasDelphiLspCapture then
        DelphiLspCmd := ' --command delphilsp.selectSettingsFile'
      else
        DelphiLspCmd := '';

      quotedCmd := QuotedVSCodeCommand;
      VSCodeWindow := FindVSCodeWindow(WorkspacePathCapture);
      if VSCodeWindow <> 0 then begin
        // VSCode window with this workspace already open: bring it to the front and reuse it
        SetForegroundWindow(VSCodeWindow);
        if LineCapture < 0 then
          cmdline := Format('cmd /c "%s --reuse-window %s%s"', [quotedCmd, WorkspacePathCapture, DelphiLspCmd])
        else
          cmdline := Format('cmd /c "%s --reuse-window %s -g %s:%d:%d%s"',
            [quotedCmd, WorkspacePathCapture, FileNameCapture, LineCapture, ColCapture, DelphiLspCmd]);
      end else begin
        // No VSCode window found for this workspace: open a new instance
        if LineCapture < 0 then
          cmdline := Format('cmd /c "%s --new-window %s%s"', [quotedCmd, WorkspacePathCapture, DelphiLspCmd])
        else
          cmdline := Format('cmd /c "%s --new-window %s -g %s:%d:%d%s"',
            [quotedCmd, WorkspacePathCapture, FileNameCapture, LineCapture, ColCapture, DelphiLspCmd]);
      end;

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
            ShowVSCodeLaunchError(
              cmdline,
              workDir,
              stdOutText,
              stdErrText,
              'ProcessExitCode',
              'code command returned a non-zero exit code.',
              exitCode);
          end);
    except
      on E: Exception do
        TThread.Queue(nil,
          procedure
          begin
            ShowVSCodeLaunchError(
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


type
  TMenuHandler = class
  strict private
    Item: TMenuItem;
    Action: TProc;
    procedure OnExecute(Sender: TObject);
    constructor Create(aCaption: string; aAction: TProc; aShortcut: string);
  class var
    MenuHandlers: TObjectList<TMenuHandler>;
    FActionList: TActionList;
  public
    destructor Destroy; override;
    procedure UpdateShortcut(AShortCut: TShortCut);
    class constructor Create;
    class destructor Destroy;
    class function AddMenuItem(NTAServices: INTAServices; aCaption: string; aAction: TProc; aShortcut: string = ''): TMenuHandler;
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
var
  MyAction: TAction;
begin
  inherited Create;
  Action := aAction;
  MyAction := TAction.Create(FActionList);
  MyAction.Caption := aCaption;
  MyAction.OnExecute := OnExecute;

  if aShortcut <> '' then
    MyAction.ShortCut := TextToShortCut(aShortcut);

  Item := TMenuItem.Create(nil);
  Item.Action := MyAction;
end;

destructor TMenuHandler.Destroy;
begin
  FreeAndNil(Item);
  inherited;
end;

procedure TMenuHandler.OnExecute(Sender: TObject);
begin
  if Assigned(Action) then
    Action;
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

procedure TryRegisterMainMenuItem; forward;

procedure TMenuRegistrationHelper.OnTimer(Sender: TObject);
begin
  TryRegisterMainMenuItem;
end;

var
  GOpenVSCodeHandler: TMenuHandler = nil;
  GOptions: TEditInVSCodeOptions = nil;
  GMenuRegistrationTimer: TTimer = nil;
  GMenuRegistrationHelper: TMenuRegistrationHelper = nil;

procedure TryRegisterMainMenuItem;
var
  NTAServices: INTAServices;
begin
  if GOpenVSCodeHandler <> nil then
    Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTAServices) then
    Exit;
  if (NTAServices.MainMenu = nil) or (NTAServices.MainMenu.Items.Count = 0) then
    Exit;

  GOpenVSCodeHandler := TMenuHandler.AddMenuItem(
    NTAServices,
    'Edit in Visual Studio Code',
    OpenCurrentFileInVisualStudioCode,
    ShortCutToText(TPluginSettings.Shortcut));

  FreeAndNil(GMenuRegistrationTimer);
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

  GOptions := TEditInVSCodeOptions.Create;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, OptionsServices) then
    OptionsServices.RegisterAddInOptions(GOptions);

  TryRegisterMainMenuItem;
  if GOpenVSCodeHandler = nil then begin
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

