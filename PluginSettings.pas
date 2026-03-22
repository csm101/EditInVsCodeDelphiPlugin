unit PluginSettings;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  Vcl.Menus;

const
  DEFAULT_VSCODE_COMMAND = 'code';
  DEFAULT_SHORTCUT_TEXT  = 'Ctrl+\';

type
  TShortcutChangedProc = reference to procedure(AShortcut: TShortCut);

  /// <summary>
  /// Persists the plugin's user-configurable settings:
  /// the VS Code executable and the keyboard shortcut.
  /// Settings are stored as JSON in %APPDATA%\EditInVSCode\settings.json.
  /// </summary>
  TPluginSettings = class
  strict private
    class var FVSCodeCommand: string;
    class var FShortcut: TShortCut;
    class var FOnShortcutChanged: TShortcutChangedProc;
    class function SettingsFilePath: string; static;
    class constructor Create;
  public
    class property VSCodeCommand: string read FVSCodeCommand write FVSCodeCommand;
    class property Shortcut: TShortCut read FShortcut write FShortcut;
    /// <summary>
    /// Called by the IDE Options frame after saving, so the menu action
    /// can update its shortcut without a circular unit dependency.
    /// </summary>
    class property OnShortcutChanged: TShortcutChangedProc
      read FOnShortcutChanged write FOnShortcutChanged;
    /// <summary>Loads settings from disk. Missing or unreadable file leaves defaults intact.</summary>
    class procedure Load;
    /// <summary>Persists current settings to disk, creating the directory if needed.</summary>
    class procedure Save;
    /// <summary>Fires OnShortcutChanged if assigned.</summary>
    class procedure NotifyShortcutChanged;
  end;

implementation

{ TPluginSettings }

class constructor TPluginSettings.Create;
begin
  FVSCodeCommand := DEFAULT_VSCODE_COMMAND;
  FShortcut := TextToShortCut(DEFAULT_SHORTCUT_TEXT);
end;

class function TPluginSettings.SettingsFilePath: string;
begin
  Result := TPath.Combine(
    TPath.Combine(GetEnvironmentVariable('APPDATA'), 'EditInVSCode'),
    'settings.json');
end;

class procedure TPluginSettings.Load;
var
  Root: TJSONObject;
  Val: TJSONValue;
  sc: TShortCut;
begin
  if not TFile.Exists(SettingsFilePath) then
    Exit;

  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(SettingsFilePath)) as TJSONObject;
  if Root = nil then
    Exit;
  try
    Val := Root.GetValue('vsCodeCommand');
    if (Val <> nil) and (Val.Value <> '') then
      FVSCodeCommand := Val.Value;

    Val := Root.GetValue('shortcut');
    if Val <> nil then begin
      sc := TextToShortCut(Val.Value);
      if sc <> 0 then
        FShortcut := sc;
    end;
  finally
    Root.Free;
  end;
end;

class procedure TPluginSettings.Save;
var
  DirPath: string;
  Root: TJSONObject;
begin
  DirPath := ExtractFilePath(SettingsFilePath);
  if not TDirectory.Exists(DirPath) then
    TDirectory.CreateDirectory(DirPath);

  Root := TJSONObject.Create;
  try
    Root.AddPair('vsCodeCommand', FVSCodeCommand);
    Root.AddPair('shortcut', ShortCutToText(FShortcut));
    TFile.WriteAllText(SettingsFilePath, Root.Format, TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

class procedure TPluginSettings.NotifyShortcutChanged;
begin
  if Assigned(FOnShortcutChanged) then
    FOnShortcutChanged(FShortcut);
end;

end.
