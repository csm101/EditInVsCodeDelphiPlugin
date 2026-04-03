unit FrmSettingsFrame;

interface

uses
  System.Classes,
  System.Generics.Collections,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Dialogs,
  PluginSettings,
  ToolsAPI;

const
  WM_REBUILD_CUSTOM_EDITOR_ROWS = WM_APP + 1;

type
  TCustomEditorRowControls = class
  public
    Panel: TPanel;
    chkEnabled: TCheckBox;
    edDisplayName: TEdit;
    hkShortcut: THotKey;
    btnCustomize: TButton;
    btnRemove: TButton;
    EditorSettings: TEditorSettings;
    destructor Destroy; override;
  end;

  TFrmSettingsFrame = class(TFrame)
    chkVSCodeEnabled: TCheckBox;
    lnkVSCodeHome: TLinkLabel;
    hkVSCodeShortcut: THotKey;
    btnVSCodeAdvanced: TButton;
    chkCursorEnabled: TCheckBox;
    lnkCursorHome: TLinkLabel;
    hkCursorShortcut: THotKey;
    btnCursorAdvanced: TButton;
    chkWindsurfEnabled: TCheckBox;
    lnkWindsurfHome: TLinkLabel;
    hkWindsurfShortcut: THotKey;
    btnWindsurfAdvanced: TButton;
    chkTraeEnabled: TCheckBox;
    lnkTraeHome: TLinkLabel;
    hkTraeShortcut: THotKey;
    btnTraeAdvanced: TButton;
    chkVSCodiumEnabled: TCheckBox;
    lnkVSCodiumHome: TLinkLabel;
    hkVSCodiumShortcut: THotKey;
    btnVSCodiumAdvanced: TButton;
    btnAddCustomEditor: TButton;
    lblBuiltInHint: TLabel;
    lblCustomEditorsHint: TLabel;
    sbCustomEditors: TScrollBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    procedure BuiltInAdvancedSettingsClick(Sender: TObject);
    procedure btnAddCustomEditorClick(Sender: TObject);
    procedure CustomEditorCustomizeClick(Sender: TObject);
    procedure CustomEditorRemoveClick(Sender: TObject);
    procedure HomePageLinkClick(Sender: TObject; const Link: string; LinkType: TSysLinkType);
  private
    FBuiltInEditorDrafts: TObjectList<TEditorSettings>;
    FCustomEditorDrafts: TObjectList<TEditorSettings>;
    FCustomEditorRows: TObjectList<TCustomEditorRowControls>;
    FFrameInitialized: Boolean;
    FPendingRemovedCustomEditor: TEditorSettings;
    FCustomEditorRowsRebuildQueued: Boolean;
    function FindBuiltInEditorDraft(const EditorId: string): TEditorSettings;
    function FindBuiltInEditor(const EditorId: string): TEditorSettings;
    function FindCustomEditorRow(Sender: TObject): TCustomEditorRowControls;
    procedure QueueCustomEditorRowsRebuild(RemovedEditor: TEditorSettings = nil);
    procedure ApplyCustomEditorDrafts;
    procedure CreateBuiltInEditorDrafts;
    procedure CreateCustomEditorDrafts;
    procedure RebuildCustomEditorRows;
    procedure LoadBuiltInEditorControls;
    procedure LoadBuiltInEditorControl(const EditorId: string; CheckBox: TCheckBox; HotKey: THotKey);
    procedure ApplyBuiltInEditorDrafts;
    procedure SaveCustomEditorControls;
    procedure SaveBuiltInEditorControls;
    procedure SaveBuiltInEditorControl(const EditorId: string; CheckBox: TCheckBox; HotKey: THotKey);
    procedure InitializeFrame;
    procedure WMRebuildCustomEditorRows(var Message: TMessage); message WM_REBUILD_CUSTOM_EDITOR_ROWS;
  public
    destructor Destroy; override;
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
  Winapi.Windows,
  Winapi.ShellAPI,
  FrmEditorAdvancedSettings;

{ TFrmSettingsFrame }

destructor TCustomEditorRowControls.Destroy;
begin
  if Panel <> nil then
    Panel.Parent := nil;
  FreeAndNil(Panel);
  inherited;
end;

procedure TFrmSettingsFrame.BuiltInAdvancedSettingsClick(Sender: TObject);
var
  EditorDraft: TEditorSettings;
begin
  SaveBuiltInEditorControls;
  SaveCustomEditorControls;

  if Sender = btnVSCodeAdvanced then
    EditorDraft := FindBuiltInEditorDraft('vscode')
  else if Sender = btnCursorAdvanced then
    EditorDraft := FindBuiltInEditorDraft('cursor')
  else if Sender = btnWindsurfAdvanced then
    EditorDraft := FindBuiltInEditorDraft('windsurf')
  else if Sender = btnTraeAdvanced then
    EditorDraft := FindBuiltInEditorDraft('trae')
  else if Sender = btnVSCodiumAdvanced then
    EditorDraft := FindBuiltInEditorDraft('vscodium')
  else
    EditorDraft := nil;

  if EditorDraft = nil then
    Exit;

  TFrmEditorAdvancedSettings.EditEditorSettings(EditorDraft);
end;

procedure TFrmSettingsFrame.btnAddCustomEditorClick(Sender: TObject);
begin
  SaveCustomEditorControls;

  var DisplayName := 'Custom Editor';
  if FCustomEditorDrafts.Count > 0 then
    DisplayName := DisplayName + ' ' + IntToStr(FCustomEditorDrafts.Count + 1);

  var EditorDraft := TPluginSettings.CreateNewCustomEditor(DisplayName);
  FCustomEditorDrafts.Add(EditorDraft);
  RebuildCustomEditorRows;
  TFrmEditorAdvancedSettings.EditEditorSettings(EditorDraft);
  RebuildCustomEditorRows;
end;

procedure TFrmSettingsFrame.CustomEditorCustomizeClick(Sender: TObject);
begin
  SaveCustomEditorControls;

  var Row := FindCustomEditorRow(Sender);
  if (Row = nil) or (Row.EditorSettings = nil) then
    Exit;

  TFrmEditorAdvancedSettings.EditEditorSettings(Row.EditorSettings);
end;

procedure TFrmSettingsFrame.CustomEditorRemoveClick(Sender: TObject);
begin
  SaveCustomEditorControls;

  var Row := FindCustomEditorRow(Sender);
  if (Row = nil) or (Row.EditorSettings = nil) then
    Exit;

  Row.Panel.Visible := False;
  Row.Panel.Enabled := False;
  QueueCustomEditorRowsRebuild(Row.EditorSettings);
end;

procedure TFrmSettingsFrame.CreateCustomEditorDrafts;
begin
  FreeAndNil(FCustomEditorDrafts);
  FCustomEditorDrafts := TObjectList<TEditorSettings>.Create(True);

  for var Editor in TPluginSettings.CustomEditors do
    FCustomEditorDrafts.Add(Editor.Clone);
end;

procedure TFrmSettingsFrame.CreateBuiltInEditorDrafts;
begin
  FreeAndNil(FBuiltInEditorDrafts);
  FBuiltInEditorDrafts := TObjectList<TEditorSettings>.Create(True);

  for var Editor in TPluginSettings.BuiltInEditors do
    FBuiltInEditorDrafts.Add(Editor.Clone);
end;

destructor TFrmSettingsFrame.Destroy;
begin
  FPendingRemovedCustomEditor := nil;
  FCustomEditorRowsRebuildQueued := False;
  FCustomEditorRows.Free;
  FCustomEditorDrafts.Free;
  FBuiltInEditorDrafts.Free;
  inherited;
end;

function TFrmSettingsFrame.FindBuiltInEditor(const EditorId: string): TEditorSettings;
begin
  Result := nil;
  for var Editor in TPluginSettings.BuiltInEditors do
    if SameText(Editor.Id, EditorId) then
      Exit(Editor);
end;

function TFrmSettingsFrame.FindBuiltInEditorDraft(const EditorId: string): TEditorSettings;
begin
  Result := nil;
  if FBuiltInEditorDrafts = nil then
    Exit;

  for var Editor in FBuiltInEditorDrafts do
    if SameText(Editor.Id, EditorId) then
      Exit(Editor);
end;

function TFrmSettingsFrame.FindCustomEditorRow(Sender: TObject): TCustomEditorRowControls;
begin
  Result := nil;
  if FCustomEditorRows = nil then
    Exit;

  for var Row in FCustomEditorRows do begin
    if Sender = Row.btnCustomize then
      Exit(Row);
    if Sender = Row.btnRemove then
      Exit(Row);
  end;
end;

procedure TFrmSettingsFrame.HomePageLinkClick(Sender: TObject; const Link: string; LinkType: TSysLinkType);
begin
  if (LinkType <> sltURL) or (Link = '') then
    Exit;

  ShellExecute(Handle, 'open', PChar(Link), nil, nil, SW_SHOWNORMAL);
end;

procedure TFrmSettingsFrame.LoadBuiltInEditorControl(const EditorId: string; CheckBox: TCheckBox; HotKey: THotKey);
begin
  var Editor := FindBuiltInEditorDraft(EditorId);
  if Editor = nil then begin
    CheckBox.Checked := False;
    CheckBox.Enabled := False;
    HotKey.HotKey := 0;
    HotKey.Enabled := False;
    Exit;
  end;

  CheckBox.Enabled := True;
  CheckBox.Checked := Editor.Enabled;
  HotKey.Enabled := True;
  HotKey.HotKey := Editor.Shortcut;
end;

procedure TFrmSettingsFrame.LoadBuiltInEditorControls;
begin
  LoadBuiltInEditorControl('vscode', chkVSCodeEnabled, hkVSCodeShortcut);
  LoadBuiltInEditorControl('cursor', chkCursorEnabled, hkCursorShortcut);
  LoadBuiltInEditorControl('windsurf', chkWindsurfEnabled, hkWindsurfShortcut);
  LoadBuiltInEditorControl('trae', chkTraeEnabled, hkTraeShortcut);
  LoadBuiltInEditorControl('vscodium', chkVSCodiumEnabled, hkVSCodiumShortcut);
end;

procedure TFrmSettingsFrame.RebuildCustomEditorRows;
begin
  if FCustomEditorRows = nil then
    FCustomEditorRows := TObjectList<TCustomEditorRowControls>.Create(True)
  else
    FCustomEditorRows.Clear;

  if FCustomEditorDrafts.Count = 0 then begin
    sbCustomEditors.VertScrollBar.Range := 0;
    lblCustomEditorsHint.Visible := True;
    Exit;
  end;

  SendMessage(sbCustomEditors.Handle, WM_SETREDRAW, 0, 0);
  try
    sbCustomEditors.DisableAlign;

    var RowTop := 0;
    for var EditorDraft in FCustomEditorDrafts do begin
      var Row := TCustomEditorRowControls.Create;
      Row.EditorSettings := EditorDraft;

      Row.Panel := TPanel.Create(nil);
      Row.Panel.Parent := sbCustomEditors;
      Row.Panel.Left := 0;
      Row.Panel.Top := RowTop;
      Row.Panel.Width := sbCustomEditors.ClientWidth - 8;
      Row.Panel.Height := 38;
      Row.Panel.BevelOuter := bvNone;

      Row.chkEnabled := TCheckBox.Create(Row.Panel);
      Row.chkEnabled.Parent := Row.Panel;
      Row.chkEnabled.Left := 8;
      Row.chkEnabled.Top := 10;
      Row.chkEnabled.Width := 17;
      Row.chkEnabled.Caption := '';
      Row.chkEnabled.Checked := EditorDraft.Enabled;

      Row.edDisplayName := TEdit.Create(Row.Panel);
      Row.edDisplayName.Parent := Row.Panel;
      Row.edDisplayName.Left := 32;
      Row.edDisplayName.Top := 8;
      Row.edDisplayName.Width := 210;
      Row.edDisplayName.Height := 21;
      Row.edDisplayName.Text := EditorDraft.DisplayName;

      Row.hkShortcut := THotKey.Create(Row.Panel);
      Row.hkShortcut.Parent := Row.Panel;
      Row.hkShortcut.Left := 250;
      Row.hkShortcut.Top := 8;
      Row.hkShortcut.Width := 120;
      Row.hkShortcut.Height := 21;
      Row.hkShortcut.HotKey := EditorDraft.Shortcut;

      Row.btnCustomize := TButton.Create(Row.Panel);
      Row.btnCustomize.Parent := Row.Panel;
      Row.btnCustomize.Left := 380;
      Row.btnCustomize.Top := 6;
      Row.btnCustomize.Width := 90;
      Row.btnCustomize.Height := 25;
      Row.btnCustomize.Caption := 'Customize';
      Row.btnCustomize.OnClick := CustomEditorCustomizeClick;

      Row.btnRemove := TButton.Create(Row.Panel);
      Row.btnRemove.Parent := Row.Panel;
      Row.btnRemove.Left := 478;
      Row.btnRemove.Top := 6;
      Row.btnRemove.Width := 75;
      Row.btnRemove.Height := 25;
      Row.btnRemove.Caption := 'Remove';
      Row.btnRemove.OnClick := CustomEditorRemoveClick;

      FCustomEditorRows.Add(Row);
      Inc(RowTop, Row.Panel.Height + 4);
    end;

    sbCustomEditors.VertScrollBar.Range := RowTop;
    lblCustomEditorsHint.Visible := False;
  finally
    sbCustomEditors.EnableAlign;
    SendMessage(sbCustomEditors.Handle, WM_SETREDRAW, 1, 0);
    RedrawWindow(sbCustomEditors.Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN);
  end;
end;

procedure TFrmSettingsFrame.InitializeFrame;
begin
  if FFrameInitialized then
    Exit;

  CreateBuiltInEditorDrafts;
  CreateCustomEditorDrafts;
  LoadBuiltInEditorControls;
  RebuildCustomEditorRows;
  FFrameInitialized := True;
end;

procedure TFrmSettingsFrame.QueueCustomEditorRowsRebuild(RemovedEditor: TEditorSettings = nil);
begin
  if RemovedEditor <> nil then
    FPendingRemovedCustomEditor := RemovedEditor;

  if FCustomEditorRowsRebuildQueued then
    Exit;

  FCustomEditorRowsRebuildQueued := True;
  PostMessage(Handle, WM_REBUILD_CUSTOM_EDITOR_ROWS, 0, 0);
end;

procedure TFrmSettingsFrame.ApplyBuiltInEditorDrafts;
begin
  for var EditorDraft in FBuiltInEditorDrafts do begin
    var Editor := FindBuiltInEditor(EditorDraft.Id);
    if Editor = nil then
      Continue;
    Editor.AssignFrom(EditorDraft);
  end;
end;

procedure TFrmSettingsFrame.ApplyCustomEditorDrafts;
begin
  SaveCustomEditorControls;
  TPluginSettings.ReplaceCustomEditors(FCustomEditorDrafts);
end;

procedure TFrmSettingsFrame.SaveCustomEditorControls;
begin
  if FCustomEditorRows = nil then
    Exit;

  for var Row in FCustomEditorRows do begin
    if Row.EditorSettings = nil then
      Continue;

    Row.EditorSettings.Enabled := Row.chkEnabled.Checked;
    Row.EditorSettings.Shortcut := Row.hkShortcut.HotKey;
    Row.EditorSettings.DisplayName := Trim(Row.edDisplayName.Text);
    if Row.EditorSettings.DisplayName = '' then
      Row.EditorSettings.DisplayName := 'Custom Editor';
  end;
end;

procedure TFrmSettingsFrame.SaveBuiltInEditorControl(const EditorId: string; CheckBox: TCheckBox; HotKey: THotKey);
begin
  var Editor := FindBuiltInEditorDraft(EditorId);
  if Editor = nil then
    Exit;

  Editor.Enabled := CheckBox.Checked;
  Editor.Shortcut := HotKey.HotKey;
end;

procedure TFrmSettingsFrame.SaveBuiltInEditorControls;
begin
  SaveBuiltInEditorControl('vscode', chkVSCodeEnabled, hkVSCodeShortcut);
  SaveBuiltInEditorControl('cursor', chkCursorEnabled, hkCursorShortcut);
  SaveBuiltInEditorControl('windsurf', chkWindsurfEnabled, hkWindsurfShortcut);
  SaveBuiltInEditorControl('trae', chkTraeEnabled, hkTraeShortcut);
  SaveBuiltInEditorControl('vscodium', chkVSCodiumEnabled, hkVSCodiumShortcut);
end;

procedure TFrmSettingsFrame.WMRebuildCustomEditorRows(var Message: TMessage);
begin
  FCustomEditorRowsRebuildQueued := False;

  if (FPendingRemovedCustomEditor <> nil) and (FCustomEditorDrafts <> nil) then begin
    var EditorToRemove := FPendingRemovedCustomEditor;
    FPendingRemovedCustomEditor := nil;
    FCustomEditorDrafts.Remove(EditorToRemove);
  end;

  RebuildCustomEditorRows;
  Message.Result := 0;
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
  FFrame.InitializeFrame;
end;

procedure TEditInVSCodeOptions.DialogClosed(Accepted: Boolean);
begin
  if not Accepted then
    Exit;
  FFrame.SaveBuiltInEditorControls;
  FFrame.SaveCustomEditorControls;
  FFrame.ApplyBuiltInEditorDrafts;
  FFrame.ApplyCustomEditorDrafts;
  TPluginSettings.Save;
  TPluginSettings.NotifyShortcutChanged;
  TPluginSettings.NotifySettingsChanged;
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
