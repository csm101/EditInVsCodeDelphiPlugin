object FrmVSCodeLaunchError: TFrmVSCodeLaunchError
  Left = 0
  Top = 0
  Caption = 'Error'
  ClientHeight = 432
  ClientWidth = 775
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object lblTitle: TLabel
    AlignWithMargins = True
    Left = 8
    Top = 8
    Width = 759
    Height = 28
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 8
    Margins.Bottom = 4
    Align = alTop
    AutoSize = False
    Caption = 'Error details'
    Layout = tlCenter
    WordWrap = True
    ExplicitWidth = 80
  end
  object memDetails: TMemo
    AlignWithMargins = True
    Left = 8
    Top = 40
    Width = 759
    Height = 340
    Margins.Left = 8
    Margins.Top = 0
    Margins.Right = 8
    Margins.Bottom = 4
    Align = alClient
    ReadOnly = True
    ScrollBars = ssBoth
    TabOrder = 0
    WordWrap = False
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 384
    Width = 775
    Height = 48
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    DesignSize = (
      775
      48)
    object lblCopyHint: TLabel
      Left = 8
      Top = 16
      Width = 245
      Height = 15
      Caption = 'Select text in the box and press Ctrl+C to copy.'
    end
    object btnClose: TButton
      Left = 677
      Top = 10
      Width = 90
      Height = 28
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Close'
      ModalResult = 1
      TabOrder = 0
    end
  end
end
