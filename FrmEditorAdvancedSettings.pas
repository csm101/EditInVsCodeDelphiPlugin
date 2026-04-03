unit FrmEditorAdvancedSettings;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  PluginSettings;

type
  TFrmEditorAdvancedSettings = class(TForm)
    lblCommand: TLabel;
    edCommand: TEdit;
    btnBrowse: TButton;
    pnlBottom: TPanel;
    btnResetToDefault: TButton;
    btnOK: TButton;
    btnCancel: TButton;
    GroupBox1: TGroupBox;
    lblWindowClassName: TLabel;
    edWindowClassName: TEdit;
    lblWindowTitleSuffix: TLabel;
    edWindowTitleSuffix: TEdit;
    GroupBox2: TGroupBox;
    lblReuseOpenArgs: TLabel;
    edReuseOpenArgs: TEdit;
    lblReuseGotoArgs: TLabel;
    edReuseGotoArgs: TEdit;
    lblNewOpenArgs: TLabel;
    edNewOpenArgs: TEdit;
    lblNewGotoArgs: TLabel;
    edNewGotoArgs: TEdit;
    lblDelphiLspArgs: TLabel;
    edDelphiLspArgs: TEdit;
    lblArgsHint: TLabel;
    procedure btnBrowseClick(Sender: TObject);
    procedure btnResetToDefaultClick(Sender: TObject);
  strict private
    FEditorId: string;
    function CreateDefaultSettingsCopy: TEditorSettings;
    function HasAllRequiredFields: Boolean;
    procedure InputChanged(Sender: TObject);
    procedure LoadFromEditorSettings(EditorSettings: TEditorSettings);
    procedure SaveToEditorSettings(EditorSettings: TEditorSettings);
    procedure UpdateOkButtonState;
  public
    class function EditEditorSettings(EditorSettings: TEditorSettings): Boolean;
  end;

implementation

{$R *.dfm}

uses
  System.SysUtils;

function TFrmEditorAdvancedSettings.CreateDefaultSettingsCopy: TEditorSettings;
begin
  Result := TPluginSettings.CreateDefaultBuiltInEditorCopy(FEditorId);
end;

function TFrmEditorAdvancedSettings.HasAllRequiredFields: Boolean;
begin
  if Trim(edCommand.Text) = '' then
    Exit(False);
  if Trim(edWindowClassName.Text) = '' then
    Exit(False);
  if Trim(edWindowTitleSuffix.Text) = '' then
    Exit(False);
  if Trim(edReuseOpenArgs.Text) = '' then
    Exit(False);
  if Trim(edReuseGotoArgs.Text) = '' then
    Exit(False);
  if Trim(edNewOpenArgs.Text) = '' then
    Exit(False);
  if Trim(edNewGotoArgs.Text) = '' then
    Exit(False);
  if Trim(edDelphiLspArgs.Text) = '' then
    Exit(False);

  Result := True;
end;

procedure TFrmEditorAdvancedSettings.InputChanged(Sender: TObject);
begin
  UpdateOkButtonState;
end;

procedure TFrmEditorAdvancedSettings.btnBrowseClick(Sender: TObject);
begin
  var Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Title := 'Select editor executable';
    Dialog.Filter := 'Scripts and executables|*.cmd;*.exe;*.bat|All files|*.*';
    Dialog.FileName := edCommand.Text;
    if Dialog.Execute(Handle) then begin
      edCommand.Text := Dialog.FileName;
      UpdateOkButtonState;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TFrmEditorAdvancedSettings.btnResetToDefaultClick(Sender: TObject);
begin
  var DefaultSettings := CreateDefaultSettingsCopy;
  try
    if DefaultSettings = nil then begin
      ShowMessage('This editor does not have built-in defaults.');
      Exit;
    end;

    LoadFromEditorSettings(DefaultSettings);
  finally
    DefaultSettings.Free;
  end;
end;

class function TFrmEditorAdvancedSettings.EditEditorSettings(EditorSettings: TEditorSettings): Boolean;
begin
  var Dialog := TFrmEditorAdvancedSettings.Create(nil);
  try
    Dialog.FEditorId := EditorSettings.Id;
    Dialog.edCommand.OnChange := Dialog.InputChanged;
    Dialog.edWindowClassName.OnChange := Dialog.InputChanged;
    Dialog.edWindowTitleSuffix.OnChange := Dialog.InputChanged;
    Dialog.edReuseOpenArgs.OnChange := Dialog.InputChanged;
    Dialog.edReuseGotoArgs.OnChange := Dialog.InputChanged;
    Dialog.edNewOpenArgs.OnChange := Dialog.InputChanged;
    Dialog.edNewGotoArgs.OnChange := Dialog.InputChanged;
    Dialog.edDelphiLspArgs.OnChange := Dialog.InputChanged;
    Dialog.LoadFromEditorSettings(EditorSettings);
    Result := Dialog.ShowModal = mrOK;
    if Result then
      Dialog.SaveToEditorSettings(EditorSettings);
  finally
    Dialog.Free;
  end;
end;

procedure TFrmEditorAdvancedSettings.LoadFromEditorSettings(EditorSettings: TEditorSettings);
begin
  if EditorSettings = nil then
    Exit;

  Caption := 'Advanced Settings - ' + EditorSettings.DisplayName;
  edCommand.Text := EditorSettings.Command;
  edWindowClassName.Text := EditorSettings.WindowClassName;
  edWindowTitleSuffix.Text := EditorSettings.WindowTitleSuffix;
  edReuseOpenArgs.Text := EditorSettings.ReuseOpenArgs;
  edReuseGotoArgs.Text := EditorSettings.ReuseGotoArgs;
  edNewOpenArgs.Text := EditorSettings.NewOpenArgs;
  edNewGotoArgs.Text := EditorSettings.NewGotoArgs;
  edDelphiLspArgs.Text := EditorSettings.DelphiLspArgs;

  var DefaultSettings := CreateDefaultSettingsCopy;
  try
    btnResetToDefault.Enabled := DefaultSettings <> nil;
  finally
    DefaultSettings.Free;
  end;

  UpdateOkButtonState;
end;

procedure TFrmEditorAdvancedSettings.SaveToEditorSettings(EditorSettings: TEditorSettings);
begin
  if EditorSettings = nil then
    Exit;

  var DefaultSettings := CreateDefaultSettingsCopy;
  try
    EditorSettings.Command := Trim(edCommand.Text);
    if (EditorSettings.Command = '') and (DefaultSettings <> nil) then
      EditorSettings.Command := DefaultSettings.Command;

    EditorSettings.WindowClassName := Trim(edWindowClassName.Text);
    if (EditorSettings.WindowClassName = '') and (DefaultSettings <> nil) then
      EditorSettings.WindowClassName := DefaultSettings.WindowClassName;

    EditorSettings.WindowTitleSuffix := Trim(edWindowTitleSuffix.Text);
    if (EditorSettings.WindowTitleSuffix = '') and (DefaultSettings <> nil) then
      EditorSettings.WindowTitleSuffix := DefaultSettings.WindowTitleSuffix;

    EditorSettings.ReuseOpenArgs := Trim(edReuseOpenArgs.Text);
    if (EditorSettings.ReuseOpenArgs = '') and (DefaultSettings <> nil) then
      EditorSettings.ReuseOpenArgs := DefaultSettings.ReuseOpenArgs;

    EditorSettings.ReuseGotoArgs := Trim(edReuseGotoArgs.Text);
    if (EditorSettings.ReuseGotoArgs = '') and (DefaultSettings <> nil) then
      EditorSettings.ReuseGotoArgs := DefaultSettings.ReuseGotoArgs;

    EditorSettings.NewOpenArgs := Trim(edNewOpenArgs.Text);
    if (EditorSettings.NewOpenArgs = '') and (DefaultSettings <> nil) then
      EditorSettings.NewOpenArgs := DefaultSettings.NewOpenArgs;

    EditorSettings.NewGotoArgs := Trim(edNewGotoArgs.Text);
    if (EditorSettings.NewGotoArgs = '') and (DefaultSettings <> nil) then
      EditorSettings.NewGotoArgs := DefaultSettings.NewGotoArgs;

    EditorSettings.DelphiLspArgs := Trim(edDelphiLspArgs.Text);
    if (EditorSettings.DelphiLspArgs = '') and (DefaultSettings <> nil) then
      EditorSettings.DelphiLspArgs := DefaultSettings.DelphiLspArgs;
  finally
    DefaultSettings.Free;
  end;
end;

procedure TFrmEditorAdvancedSettings.UpdateOkButtonState;
begin
  btnOK.Enabled := HasAllRequiredFields;
end;

end.