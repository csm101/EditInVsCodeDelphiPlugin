unit PluginSettings;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  Vcl.Menus;

const
  SETTINGS_FORMAT_VERSION = 2;
  DEFAULT_WINDOW_CLASS_NAME = 'Chrome_WidgetWin_1';
  DEFAULT_VSCODE_COMMAND = 'code';
  DEFAULT_SHORTCUT_TEXT  = 'Ctrl+\';
  DEFAULT_REUSE_OPEN_ARGS = '--reuse-window {workspacePath}';
  DEFAULT_REUSE_GOTO_ARGS = '--reuse-window {workspacePath} -g {gotoTarget}';
  DEFAULT_NEW_OPEN_ARGS = '--new-window {workspacePath}';
  DEFAULT_NEW_GOTO_ARGS = '--new-window {workspacePath} -g {gotoTarget}';
  DEFAULT_DELPHI_LSP_ARGS = '--command delphilsp.selectSettingsFile';

type
  TShortcutChangedProc = reference to procedure(AShortcut: TShortCut);
  TSettingsChangedProc = reference to procedure;

  TEditorSettings = class
  strict private
    FId: string;
    FDisplayName: string;
    FHomepageUrl: string;
    FEnabled: Boolean;
    FCommand: string;
    FShortcut: TShortCut;
    FWindowClassName: string;
    FWindowTitleSuffix: string;
    FReuseOpenArgs: string;
    FReuseGotoArgs: string;
    FNewOpenArgs: string;
    FNewGotoArgs: string;
    FDelphiLspArgs: string;
  public
    constructor Create(const AId, ADisplayName, AHomepageUrl: string; AEnabled: Boolean;
      const ACommand: string; AShortcut: TShortCut; const AWindowClassName,
      AWindowTitleSuffix, AReuseOpenArgs, AReuseGotoArgs, ANewOpenArgs,
      ANewGotoArgs, ADelphiLspArgs: string);
    procedure AssignFrom(Source: TEditorSettings; IncludeIdentity: Boolean = False);
    function Clone: TEditorSettings;
    procedure LoadFromJson(JsonObject: TJSONObject; LoadIdentity: Boolean = False);
    function ToJson: TJSONObject;
    property Id: string read FId;
    property DisplayName: string read FDisplayName write FDisplayName;
    property HomepageUrl: string read FHomepageUrl write FHomepageUrl;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Command: string read FCommand write FCommand;
    property Shortcut: TShortCut read FShortcut write FShortcut;
    property WindowClassName: string read FWindowClassName write FWindowClassName;
    property WindowTitleSuffix: string read FWindowTitleSuffix write FWindowTitleSuffix;
    property ReuseOpenArgs: string read FReuseOpenArgs write FReuseOpenArgs;
    property ReuseGotoArgs: string read FReuseGotoArgs write FReuseGotoArgs;
    property NewOpenArgs: string read FNewOpenArgs write FNewOpenArgs;
    property NewGotoArgs: string read FNewGotoArgs write FNewGotoArgs;
    property DelphiLspArgs: string read FDelphiLspArgs write FDelphiLspArgs;
  end;

  /// Persists the plugin's user-configurable settings.
  ///
  /// The current on-disk format stores multiple built-in editor profiles plus
  /// optional custom editors. For backwards compatibility, the existing
  /// VSCodeCommand and Shortcut properties still map to the built-in VS Code
  /// profile so the rest of the plugin can keep working unchanged while the
  /// broader multi-editor rollout is implemented in subsequent phases.
  ///
  TPluginSettings = class
  strict private
    class var FBuiltInEditors: TObjectList<TEditorSettings>;
    class var FCustomEditors: TObjectList<TEditorSettings>;
    class var FOnShortcutChanged: TShortcutChangedProc;
    class var FOnSettingsChanged: TSettingsChangedProc;
    class function SettingsFilePath: string; static;
    class procedure ResetToDefaults; static;
    class procedure AddDefaultBuiltInEditors; static;
    class function CreateBuiltInEditor(const EditorId, DisplayName, HomepageUrl,
      Command, WindowTitleSuffix: string; Enabled: Boolean; Shortcut: TShortCut): TEditorSettings; static;
    class function CreateCustomEditorFromJson(JsonObject: TJSONObject): TEditorSettings; static;
    class function FindBuiltInEditor(const EditorId: string): TEditorSettings; static;
    class function GetVSCodeEditor: TEditorSettings; static;
    class function GetVSCodeCommand: string; static;
    class procedure SetVSCodeCommand(const Value: string); static;
    class function GetVSCodeShortcut: TShortCut; static;
    class procedure SetVSCodeShortcut(const Value: TShortCut); static;
    class procedure LoadLegacySettings(Root: TJSONObject); static;
    class procedure LoadNewSettings(Root: TJSONObject); static;
    class constructor Create;
    class destructor Destroy;
  public
    class property VSCodeCommand: string read GetVSCodeCommand write SetVSCodeCommand;
    class property Shortcut: TShortCut read GetVSCodeShortcut write SetVSCodeShortcut;
    /// <summary>
    /// Called by the IDE Options frame after saving, so the menu action
    /// can update its shortcut without a circular unit dependency.
    /// </summary>
    class property OnShortcutChanged: TShortcutChangedProc
      read FOnShortcutChanged write FOnShortcutChanged;
    class property OnSettingsChanged: TSettingsChangedProc
      read FOnSettingsChanged write FOnSettingsChanged;
    /// <summary>Loads settings from disk. Missing or unreadable file leaves defaults intact.</summary>
    class procedure Load;
    /// <summary>Persists current settings to disk, creating the directory if needed.</summary>
    class procedure Save;
    /// <summary>Fires OnShortcutChanged if assigned.</summary>
    class procedure NotifyShortcutChanged;
    class procedure NotifySettingsChanged;
    class function CreateDefaultBuiltInEditorCopy(const EditorId: string): TEditorSettings;
    class function CreateNewCustomEditor(const DisplayName: string): TEditorSettings;
    class procedure ReplaceCustomEditors(SourceEditors: TObjectList<TEditorSettings>);
    class function BuiltInEditors: TArray<TEditorSettings>;
    class function CustomEditors: TArray<TEditorSettings>;
  end;

implementation

function ParseStoredShortcutText(const ShortcutText: string; DefaultValue: TShortCut): TShortCut;
begin
  if ShortcutText = '' then begin
    Result := 0;
    Exit;
  end;

  var ParsedShortcut := TextToShortCut(ShortcutText);
  if ParsedShortcut = 0 then begin
    Result := DefaultValue;
    Exit;
  end;

  Result := ParsedShortcut;
end;

function ShortcutToStoredText(AShortCut: TShortCut): string;
begin
  if AShortCut = 0 then begin
    Result := '';
    Exit;
  end;
  Result := ShortCutToText(AShortCut);
end;

{ TEditorSettings }

constructor TEditorSettings.Create(const AId, ADisplayName, AHomepageUrl: string;
  AEnabled: Boolean; const ACommand: string; AShortcut: TShortCut;
  const AWindowClassName, AWindowTitleSuffix, AReuseOpenArgs, AReuseGotoArgs,
  ANewOpenArgs, ANewGotoArgs, ADelphiLspArgs: string);
begin
  inherited Create;
  FId := AId;
  FDisplayName := ADisplayName;
  FHomepageUrl := AHomepageUrl;
  FEnabled := AEnabled;
  FCommand := ACommand;
  FShortcut := AShortcut;
  FWindowClassName := AWindowClassName;
  FWindowTitleSuffix := AWindowTitleSuffix;
  FReuseOpenArgs := AReuseOpenArgs;
  FReuseGotoArgs := AReuseGotoArgs;
  FNewOpenArgs := ANewOpenArgs;
  FNewGotoArgs := ANewGotoArgs;
  FDelphiLspArgs := ADelphiLspArgs;
end;

procedure TEditorSettings.AssignFrom(Source: TEditorSettings; IncludeIdentity: Boolean = False);
begin
  if Source = nil then
    Exit;

  if IncludeIdentity then
    FId := Source.Id;
  FDisplayName := Source.DisplayName;
  FHomepageUrl := Source.HomepageUrl;
  FEnabled := Source.Enabled;
  FCommand := Source.Command;
  FShortcut := Source.Shortcut;
  FWindowClassName := Source.WindowClassName;
  FWindowTitleSuffix := Source.WindowTitleSuffix;
  FReuseOpenArgs := Source.ReuseOpenArgs;
  FReuseGotoArgs := Source.ReuseGotoArgs;
  FNewOpenArgs := Source.NewOpenArgs;
  FNewGotoArgs := Source.NewGotoArgs;
  FDelphiLspArgs := Source.DelphiLspArgs;
end;

function TEditorSettings.Clone: TEditorSettings;
begin
  Result := TEditorSettings.Create(
    FId,
    FDisplayName,
    FHomepageUrl,
    FEnabled,
    FCommand,
    FShortcut,
    FWindowClassName,
    FWindowTitleSuffix,
    FReuseOpenArgs,
    FReuseGotoArgs,
    FNewOpenArgs,
    FNewGotoArgs,
    FDelphiLspArgs);
end;

procedure TEditorSettings.LoadFromJson(JsonObject: TJSONObject; LoadIdentity: Boolean = False);
begin
  if JsonObject = nil then
    Exit;

  var JsonValue: TJSONValue;
  if LoadIdentity then begin
    JsonValue := JsonObject.GetValue('id');
    if JsonValue <> nil then
      FId := JsonValue.Value;
  end;

  JsonValue := JsonObject.GetValue('displayName');
  if JsonValue <> nil then
    FDisplayName := JsonValue.Value;

  JsonValue := JsonObject.GetValue('homepageUrl');
  if JsonValue <> nil then
    FHomepageUrl := JsonValue.Value;

  JsonValue := JsonObject.GetValue('enabled');
  if JsonValue <> nil then
    FEnabled := SameText(JsonValue.Value, 'true');

  JsonValue := JsonObject.GetValue('command');
  if JsonValue <> nil then
    FCommand := JsonValue.Value;

  JsonValue := JsonObject.GetValue('shortcut');
  if JsonValue <> nil then
    FShortcut := ParseStoredShortcutText(JsonValue.Value, FShortcut);

  JsonValue := JsonObject.GetValue('windowClassName');
  if JsonValue <> nil then
    FWindowClassName := JsonValue.Value;

  JsonValue := JsonObject.GetValue('windowTitleSuffix');
  if JsonValue <> nil then
    FWindowTitleSuffix := JsonValue.Value;

  JsonValue := JsonObject.GetValue('reuseOpenArgs');
  if JsonValue <> nil then
    FReuseOpenArgs := JsonValue.Value;

  JsonValue := JsonObject.GetValue('reuseGotoArgs');
  if JsonValue <> nil then
    FReuseGotoArgs := JsonValue.Value;

  JsonValue := JsonObject.GetValue('newOpenArgs');
  if JsonValue <> nil then
    FNewOpenArgs := JsonValue.Value;

  JsonValue := JsonObject.GetValue('newGotoArgs');
  if JsonValue <> nil then
    FNewGotoArgs := JsonValue.Value;

  JsonValue := JsonObject.GetValue('delphiLspArgs');
  if JsonValue <> nil then
    FDelphiLspArgs := JsonValue.Value;
end;

function TEditorSettings.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', FId);
  Result.AddPair('displayName', FDisplayName);
  Result.AddPair('homepageUrl', FHomepageUrl);
  Result.AddPair('enabled', TJSONBool.Create(FEnabled));
  Result.AddPair('command', FCommand);
  Result.AddPair('shortcut', ShortcutToStoredText(FShortcut));
  Result.AddPair('windowClassName', FWindowClassName);
  Result.AddPair('windowTitleSuffix', FWindowTitleSuffix);
  Result.AddPair('reuseOpenArgs', FReuseOpenArgs);
  Result.AddPair('reuseGotoArgs', FReuseGotoArgs);
  Result.AddPair('newOpenArgs', FNewOpenArgs);
  Result.AddPair('newGotoArgs', FNewGotoArgs);
  Result.AddPair('delphiLspArgs', FDelphiLspArgs);
end;

{ TPluginSettings }

class constructor TPluginSettings.Create;
begin
  FBuiltInEditors := TObjectList<TEditorSettings>.Create(True);
  FCustomEditors := TObjectList<TEditorSettings>.Create(True);
  ResetToDefaults;
end;

class destructor TPluginSettings.Destroy;
begin
  FBuiltInEditors.Free;
  FCustomEditors.Free;
end;

class function TPluginSettings.SettingsFilePath: string;
begin
  Result := TPath.Combine(
    TPath.Combine(GetEnvironmentVariable('APPDATA'), 'EditInVSCode'),
    'settings.json');
end;

class procedure TPluginSettings.ResetToDefaults;
begin
  FBuiltInEditors.Clear;
  FCustomEditors.Clear;
  AddDefaultBuiltInEditors;
end;

class procedure TPluginSettings.AddDefaultBuiltInEditors;
begin
  for var EditorId in ['vscode', 'cursor', 'windsurf', 'trae', 'vscodium'] do
    FBuiltInEditors.Add(CreateDefaultBuiltInEditorCopy(EditorId));
end;

class function TPluginSettings.CreateBuiltInEditor(const EditorId, DisplayName,
  HomepageUrl, Command, WindowTitleSuffix: string; Enabled: Boolean;
  Shortcut: TShortCut): TEditorSettings;
begin
  Result := TEditorSettings.Create(
    EditorId,
    DisplayName,
    HomepageUrl,
    Enabled,
    Command,
    Shortcut,
    DEFAULT_WINDOW_CLASS_NAME,
    WindowTitleSuffix,
    DEFAULT_REUSE_OPEN_ARGS,
    DEFAULT_REUSE_GOTO_ARGS,
    DEFAULT_NEW_OPEN_ARGS,
    DEFAULT_NEW_GOTO_ARGS,
    DEFAULT_DELPHI_LSP_ARGS);
end;

class function TPluginSettings.CreateCustomEditorFromJson(JsonObject: TJSONObject): TEditorSettings;
begin
  Result := TEditorSettings.Create(
    '', '', '', False, '', 0, DEFAULT_WINDOW_CLASS_NAME, '',
    DEFAULT_REUSE_OPEN_ARGS, DEFAULT_REUSE_GOTO_ARGS,
    DEFAULT_NEW_OPEN_ARGS, DEFAULT_NEW_GOTO_ARGS, '');
  Result.LoadFromJson(JsonObject, True);
end;

class function TPluginSettings.CreateDefaultBuiltInEditorCopy(const EditorId: string): TEditorSettings;
begin
  if SameText(EditorId, 'vscode') then begin
    Result := CreateBuiltInEditor(
      'vscode', 'Visual Studio Code', 'https://code.visualstudio.com/',
      DEFAULT_VSCODE_COMMAND, 'Visual Studio Code', True,
      TextToShortCut(DEFAULT_SHORTCUT_TEXT));
    Exit;
  end;

  if SameText(EditorId, 'cursor') then begin
    Result := CreateBuiltInEditor(
      'cursor', 'Cursor', 'https://cursor.com/',
      'cursor', 'Cursor', False, 0);
    Exit;
  end;

  if SameText(EditorId, 'windsurf') then begin
    Result := CreateBuiltInEditor(
      'windsurf', 'Windsurf', 'https://windsurf.com/editor',
      'windsurf', 'Windsurf', False, 0);
    Exit;
  end;

  if SameText(EditorId, 'trae') then begin
    Result := CreateBuiltInEditor(
      'trae', 'TRAE', 'https://www.trae.ai/',
      'trae', 'TRAE', False, 0);
    Exit;
  end;

  if SameText(EditorId, 'vscodium') then begin
    Result := CreateBuiltInEditor(
      'vscodium', 'VSCodium', 'https://vscodium.com/',
      'codium', 'VSCodium', False, 0);
    Exit;
  end;

  Result := nil;
end;

class function TPluginSettings.CreateNewCustomEditor(const DisplayName: string): TEditorSettings;
begin
  var CustomId := 'custom-' + StringReplace(GuidToString(TGUID.NewGuid), '-', '', [rfReplaceAll]);
  CustomId := StringReplace(CustomId, '{', '', [rfReplaceAll]);
  CustomId := StringReplace(CustomId, '}', '', [rfReplaceAll]);
  Result := TEditorSettings.Create(
    CustomId,
    DisplayName,
    '',
    False,
    '',
    0,
    DEFAULT_WINDOW_CLASS_NAME,
    '',
    DEFAULT_REUSE_OPEN_ARGS,
    DEFAULT_REUSE_GOTO_ARGS,
    DEFAULT_NEW_OPEN_ARGS,
    DEFAULT_NEW_GOTO_ARGS,
    '');
end;

class procedure TPluginSettings.ReplaceCustomEditors(SourceEditors: TObjectList<TEditorSettings>);
begin
  FCustomEditors.Clear;
  if SourceEditors = nil then
    Exit;

  for var SourceEditor in SourceEditors do
    FCustomEditors.Add(SourceEditor.Clone);
end;

class function TPluginSettings.FindBuiltInEditor(const EditorId: string): TEditorSettings;
begin
  Result := nil;
  for var Editor in FBuiltInEditors do
    if SameText(Editor.Id, EditorId) then
    begin
      Result := Editor;
      Exit;
    end;
end;

class function TPluginSettings.GetVSCodeEditor: TEditorSettings;
begin
  Result := FindBuiltInEditor('vscode');
end;

class function TPluginSettings.GetVSCodeCommand: string;
begin
  var VSCodeEditor := GetVSCodeEditor;
  if VSCodeEditor = nil then begin
    Result := DEFAULT_VSCODE_COMMAND;
    Exit;
  end;
  Result := VSCodeEditor.Command;
end;

class procedure TPluginSettings.SetVSCodeCommand(const Value: string);
begin
  var VSCodeEditor := GetVSCodeEditor;
  if VSCodeEditor = nil then
    Exit;
  VSCodeEditor.Enabled := True;
  VSCodeEditor.Command := Value;
end;

class function TPluginSettings.GetVSCodeShortcut: TShortCut;
begin
  var VSCodeEditor := GetVSCodeEditor;
  if VSCodeEditor = nil then begin
    Result := TextToShortCut(DEFAULT_SHORTCUT_TEXT);
    Exit;
  end;
  Result := VSCodeEditor.Shortcut;
end;

class procedure TPluginSettings.SetVSCodeShortcut(const Value: TShortCut);
begin
  var VSCodeEditor := GetVSCodeEditor;
  if VSCodeEditor = nil then
    Exit;
  VSCodeEditor.Enabled := True;
  VSCodeEditor.Shortcut := Value;
end;

class procedure TPluginSettings.LoadLegacySettings(Root: TJSONObject);
begin
  var VSCodeEditor := GetVSCodeEditor;
  if VSCodeEditor = nil then
    Exit;

  var JsonValue := Root.GetValue('vsCodeCommand');
  if (JsonValue <> nil) and (Trim(JsonValue.Value) <> '') then
    VSCodeEditor.Command := JsonValue.Value;

  JsonValue := Root.GetValue('shortcut');
  if JsonValue <> nil then
    VSCodeEditor.Shortcut := ParseStoredShortcutText(JsonValue.Value, VSCodeEditor.Shortcut);
end;

class procedure TPluginSettings.LoadNewSettings(Root: TJSONObject);
begin
  var BuiltInEditorsArray := Root.GetValue('builtInEditors') as TJSONArray;
  if BuiltInEditorsArray <> nil then
    for var BuiltInEditorValue in BuiltInEditorsArray do begin
      var BuiltInEditorObject := BuiltInEditorValue as TJSONObject;
      if BuiltInEditorObject = nil then
        Continue;

      var IdValue := BuiltInEditorObject.GetValue('id');
      if IdValue = nil then
        Continue;

      var BuiltInEditor := FindBuiltInEditor(IdValue.Value);
      if BuiltInEditor = nil then
        Continue;

      BuiltInEditor.LoadFromJson(BuiltInEditorObject);
    end;

  FCustomEditors.Clear;
  var CustomEditorsArray := Root.GetValue('customEditors') as TJSONArray;
  if CustomEditorsArray = nil then
    Exit;

  for var CustomEditorValue in CustomEditorsArray do begin
    var CustomEditorObject := CustomEditorValue as TJSONObject;
    if CustomEditorObject = nil then
      Continue;
    FCustomEditors.Add(CreateCustomEditorFromJson(CustomEditorObject));
  end;
end;

class procedure TPluginSettings.Load;
var
  Root: TJSONObject;
begin
  ResetToDefaults;

  if not TFile.Exists(SettingsFilePath) then
    Exit;

  try
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(SettingsFilePath, TEncoding.UTF8)) as TJSONObject;
  except
    Exit;
  end;

  if Root = nil then
    Exit;
  try
    if Root.GetValue('builtInEditors') <> nil then begin
      LoadNewSettings(Root);
      Exit;
    end;

    if (Root.GetValue('vsCodeCommand') <> nil) or (Root.GetValue('shortcut') <> nil) then begin
      LoadLegacySettings(Root);
      Save;
    end;
  finally
    Root.Free;
  end;
end;

class procedure TPluginSettings.Save;
var
  DirPath: string;
  Root: TJSONObject;
  BuiltInEditorsArray: TJSONArray;
  CustomEditorsArray: TJSONArray;
begin
  DirPath := ExtractFilePath(SettingsFilePath);
  if not TDirectory.Exists(DirPath) then
    TDirectory.CreateDirectory(DirPath);

  Root := TJSONObject.Create;
  try
    Root.AddPair('formatVersion', TJSONNumber.Create(SETTINGS_FORMAT_VERSION));

    BuiltInEditorsArray := TJSONArray.Create;
    for var BuiltInEditor in FBuiltInEditors do
      BuiltInEditorsArray.AddElement(BuiltInEditor.ToJson);
    Root.AddPair('builtInEditors', BuiltInEditorsArray);

    CustomEditorsArray := TJSONArray.Create;
    for var CustomEditor in FCustomEditors do
      CustomEditorsArray.AddElement(CustomEditor.ToJson);
    Root.AddPair('customEditors', CustomEditorsArray);

    TFile.WriteAllText(SettingsFilePath, Root.Format, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

class procedure TPluginSettings.NotifyShortcutChanged;
begin
  if Assigned(FOnShortcutChanged) then
    FOnShortcutChanged(Shortcut);
end;

class procedure TPluginSettings.NotifySettingsChanged;
begin
  if Assigned(FOnSettingsChanged) then
    FOnSettingsChanged;
end;

class function TPluginSettings.BuiltInEditors: TArray<TEditorSettings>;
begin
  Result := FBuiltInEditors.ToArray;
end;

class function TPluginSettings.CustomEditors: TArray<TEditorSettings>;
begin
  Result := FCustomEditors.ToArray;
end;

end.
