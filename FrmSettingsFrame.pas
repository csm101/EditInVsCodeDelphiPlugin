unit FrmSettingsFrame;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  ToolsAPI;

type
  TFrmSettingsFrame = class(TFrame)
    lblVSCodeCommand: TLabel;
    edVSCodeCommand: TEdit;
    btnBrowse: TButton;
    lblCommandHint: TLabel;
    lblShortcut: TLabel;
    hkShortcut: THotKey;
    lblShortcutHint: TLabel;
    procedure btnBrowseClick(Sender: TObject);
  end;

  /// <summary>
  /// Registers the plugin's settings into the IDE Tools > Options... dialog.
  /// The IDE calls GetFrameClass to instantiate TFrmSettingsFrame, then
  /// FrameCreated to populate it, and DialogClosed to apply changes.
  /// The object is NOT reference-counted (_AddRef/_Release return -1):
  /// lifetime is managed explicitly by the plugin via FreeAndNil.
  /// </summary>
  TEditInVSCodeOptions = class(TInterfacedObject, INTAAddInOptions)
  strict private
    FFrame: TFrmSettingsFrame;
  protected
    // IInterface - non-reference-counted: lifetime managed by owner
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

implementation

{$R *.dfm}

uses
  System.SysUtils,
  Vcl.Menus,
  PluginSettings;

{ TFrmSettingsFrame }

procedure TFrmSettingsFrame.btnBrowseClick(Sender: TObject);
var
  dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create(nil);
  try
    dlg.Title := 'Select VS Code Executable';
    dlg.Filter := 'Scripts and executables|*.cmd;*.exe;*.bat|All files|*.*';
    dlg.FileName := edVSCodeCommand.Text;
    if dlg.Execute(Handle) then
      edVSCodeCommand.Text := dlg.FileName;
  finally
    dlg.Free;
  end;
end;

function TEditInVSCodeOptions._AddRef: Integer;
begin
  Result := -1; // not reference-counted
end;

function TEditInVSCodeOptions._Release: Integer;
begin
  Result := -1; // not reference-counted
end;

{ TEditInVSCodeOptions }

function TEditInVSCodeOptions.GetArea: string;
begin
  Result := 'Third Party';
end;

function TEditInVSCodeOptions.GetCaption: string;
begin
  Result := 'Edit in VS Code';
end;

function TEditInVSCodeOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TFrmSettingsFrame;
end;

procedure TEditInVSCodeOptions.FrameCreated(AFrame: TCustomFrame);
begin
  FFrame := AFrame as TFrmSettingsFrame;
  FFrame.edVSCodeCommand.Text := TPluginSettings.VSCodeCommand;
  FFrame.hkShortcut.HotKey   := TPluginSettings.Shortcut;
end;

procedure TEditInVSCodeOptions.DialogClosed(Accepted: Boolean);
var
  newCmd: string;
begin
  if not Accepted then
    Exit;
  newCmd := Trim(FFrame.edVSCodeCommand.Text);
  if newCmd = '' then
    newCmd := DEFAULT_VSCODE_COMMAND;
  TPluginSettings.VSCodeCommand := newCmd;
  TPluginSettings.Shortcut      := FFrame.hkShortcut.HotKey;
  TPluginSettings.Save;
  TPluginSettings.NotifyShortcutChanged;
end;

function TEditInVSCodeOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TEditInVSCodeOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TEditInVSCodeOptions.IncludeInIDEInsight: Boolean;
begin
  // This page is small and self-contained. Keeping it out of IDE Insight
  // avoids extra indexing work when the IDE builds preferences metadata.
  Result := False;
end;

end.
