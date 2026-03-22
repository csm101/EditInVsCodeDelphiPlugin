object FrmSettingsFrame: TFrmSettingsFrame
  Left = 0
  Top = 0
  Width = 500
  Height = 186
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  TabOrder = 0
  object lblVSCodeCommand: TLabel
    Left = 16
    Top = 16
    Width = 159
    Height = 13
    Caption = 'Visual Studio Code executable:'
  end
  object lblCommandHint: TLabel
    Left = 16
    Top = 68
    Width = 468
    Height = 28
    AutoSize = False
    Caption =
      'Leave as '#39'code'#39' if VS Code is in PATH, or enter the full path to' +
      ' the executable (e.g. code.cmd or code.exe).'
    WordWrap = True
  end
  object lblShortcut: TLabel
    Left = 16
    Top = 110
    Width = 97
    Height = 13
    Caption = 'Keyboard shortcut:'
  end
  object lblShortcutHint: TLabel
    Left = 16
    Top = 162
    Width = 290
    Height = 13
    Caption = 'The shortcut takes effect after clicking OK.'
  end
  object edVSCodeCommand: TEdit
    Left = 16
    Top = 36
    Width = 380
    Height = 21
    TabOrder = 0
  end
  object btnBrowse: TButton
    Left = 404
    Top = 34
    Width = 80
    Height = 25
    Caption = 'Browse...'
    TabOrder = 1
    OnClick = btnBrowseClick
  end
  object hkShortcut: THotKey
    Left = 16
    Top = 129
    Width = 200
    Height = 21
    HotKey = 0
    Modifiers = []
    TabOrder = 2
  end
end
