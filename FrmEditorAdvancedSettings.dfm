object FrmEditorAdvancedSettings: TFrmEditorAdvancedSettings
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Advanced Settings'
  ClientHeight = 565
  ClientWidth = 631
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object lblCommand: TLabel
    Left = 8
    Top = 8
    Width = 158
    Height = 15
    Caption = 'Executable command / path:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object edCommand: TEdit
    Left = 8
    Top = 28
    Width = 520
    Height = 23
    TabOrder = 0
  end
  object btnBrowse: TButton
    Left = 544
    Top = 26
    Width = 80
    Height = 25
    Caption = 'Browse...'
    TabOrder = 1
    OnClick = btnBrowseClick
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 517
    Width = 631
    Height = 48
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    object btnResetToDefault: TButton
      Left = 16
      Top = 10
      Width = 120
      Height = 25
      Caption = 'Reset to Default'
      TabOrder = 0
      OnClick = btnResetToDefaultClick
    end
    object btnOK: TButton
      Left = 456
      Top = 10
      Width = 80
      Height = 25
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 1
    end
    object btnCancel: TButton
      Left = 544
      Top = 10
      Width = 80
      Height = 25
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 2
    end
  end
  object GroupBox1: TGroupBox
    Left = 8
    Top = 57
    Width = 616
    Height = 120
    Caption = 'Existing open instances Detection'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 3
    object lblWindowClassName: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 606
      Height = 15
      Align = alTop
      Caption = 
        'Window class name to search for: (Usually "Chrome_WidgetWin_1" f' +
        'or Electron based editors)'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 494
    end
    object lblWindowTitleSuffix: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 70
      Width = 606
      Height = 15
      Align = alTop
      Caption = 'Window title suffix / match text:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 168
    end
    object edWindowClassName: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 41
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
    end
    object edWindowTitleSuffix: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 91
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 1
    end
  end
  object GroupBox2: TGroupBox
    AlignWithMargins = True
    Left = 8
    Top = 183
    Width = 616
    Height = 328
    Caption = 'Command Line Parameters'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 4
    object lblReuseOpenArgs: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 20
      Width = 606
      Height = 15
      Align = alTop
      Caption = 'Reuse existing window, no goto line/col:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 213
    end
    object lblReuseGotoArgs: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 70
      Width = 606
      Height = 15
      Align = alTop
      Caption = 'Reuse existing window, goto line/col:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 196
    end
    object lblNewOpenArgs: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 120
      Width = 606
      Height = 15
      Align = alTop
      Caption = 'Open new window only:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 128
    end
    object lblNewGotoArgs: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 170
      Width = 606
      Height = 15
      Align = alTop
      Caption = 'Open new + goto:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 96
    end
    object lblDelphiLspArgs: TLabel
      AlignWithMargins = True
      Left = 5
      Top = 220
      Width = 606
      Height = 15
      Align = alTop
      Caption = 'Extra args when .delphilsp exists:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ExplicitWidth = 170
    end
    object lblArgsHint: TLabel
      AlignWithMargins = True
      Left = 22
      Top = 270
      Width = 589
      Height = 45
      Margins.Left = 20
      Margins.Bottom = 10
      Align = alTop
      AutoSize = False
      Caption = 
        'Supported placeholders: '#13#10'   {workspacePath}, {filePath}, {gotoT' +
        'arget}, {line}, {column}. '#13#10'The launcher expands them and then a' +
        'ppends DelphiLSP arguments when needed.'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      WordWrap = True
      ExplicitTop = 264
    end
    object edReuseOpenArgs: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 41
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
    end
    object edReuseGotoArgs: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 91
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 1
    end
    object edNewOpenArgs: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 141
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 2
    end
    object edNewGotoArgs: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 191
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 3
    end
    object edDelphiLspArgs: TEdit
      AlignWithMargins = True
      Left = 5
      Top = 241
      Width = 606
      Height = 23
      Align = alTop
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      TabOrder = 4
    end
  end
end
