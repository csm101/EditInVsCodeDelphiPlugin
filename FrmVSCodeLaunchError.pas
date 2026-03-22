unit FrmVSCodeLaunchError;

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms;

type
  TFrmVSCodeLaunchError = class(TForm)
    lblTitle: TLabel;
    memDetails: TMemo;
    pnlBottom: TPanel;
    lblCopyHint: TLabel;
    btnClose: TButton;
  public
    class procedure ShowDialog(const ACaption, ATitle, ADetails: string);
  end;

implementation

{$R *.dfm}

class procedure TFrmVSCodeLaunchError.ShowDialog(const ACaption, ATitle,
  ADetails: string);
begin
  var Dialog := TFrmVSCodeLaunchError.Create(nil);
  try
    Dialog.Caption := ACaption;
    Dialog.lblTitle.Caption := ATitle;
    Dialog.memDetails.Lines.Text := ADetails;
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

end.
