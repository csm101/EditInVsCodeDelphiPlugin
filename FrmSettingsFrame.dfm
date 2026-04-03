object FrmSettingsFrame: TFrmSettingsFrame
  Left = 0
  Top = 0
  Width = 611
  Height = 511
  TabOrder = 0
  object lblBuiltInHint: TLabel
    Left = 16
    Top = 0
    Width = 505
    Height = 15
    Caption =
      'Select the editor(s) that should appear in the Tools menu. Short' +
      'cuts take effect after clicking OK.'
  end
  object lblCustomEditorsHint: TLabel
    Left = 16
    Top = 319
    Width = 332
    Height = 30
    Caption =
      'If your are using another code editor forked from Visual Studio,' +
      #13#10' you can configure it here:'
  end
  object Label1: TLabel
    Left = 52
    Top = 50
    Width = 38
    Height = 15
    Caption = 'Hotkey'
  end
  object Label2: TLabel
    Left = 52
    Top = 108
    Width = 38
    Height = 15
    Caption = 'Hotkey'
  end
  object Label3: TLabel
    Left = 52
    Top = 166
    Width = 38
    Height = 15
    Caption = 'Hotkey'
  end
  object Label4: TLabel
    Left = 52
    Top = 224
    Width = 38
    Height = 15
    Caption = 'Hotkey'
  end
  object Label5: TLabel
    Left = 52
    Top = 282
    Width = 38
    Height = 15
    Caption = 'Hotkey'
  end
  object chkVSCodeEnabled: TCheckBox
    Left = 16
    Top = 22
    Width = 121
    Height = 17
    Caption = 'Visual Studio Code'
    TabOrder = 0
  end
  object lnkVSCodeHome: TLinkLabel
    Left = 152
    Top = 22
    Width = 128
    Height = 19
    Caption =
      '<a href="https://code.visualstudio.com/">code.visualstudio.com/<' +
      '/a>'
    TabOrder = 1
    OnLinkClick = HomePageLinkClick
  end
  object hkVSCodeShortcut: THotKey
    Left = 94
    Top = 47
    Width = 105
    Height = 23
    HotKey = 0
    Modifiers = []
    TabOrder = 2
  end
  object btnVSCodeClearShortcut: TButton
    Left = 205
    Top = 45
    Width = 44
    Height = 25
    Caption = 'Clear'
    TabOrder = 3
    OnClick = BuiltInClearShortcutClick
  end
  object btnVSCodeAdvanced: TButton
    Left = 255
    Top = 45
    Width = 130
    Height = 25
    Caption = 'Advanced Settings...'
    TabOrder = 4
    OnClick = BuiltInAdvancedSettingsClick
  end
  object chkCursorEnabled: TCheckBox
    Left = 16
    Top = 80
    Width = 121
    Height = 17
    Caption = 'Cursor'
    TabOrder = 4
  end
  object lnkCursorHome: TLinkLabel
    Left = 152
    Top = 80
    Width = 69
    Height = 19
    Caption = '<a href="https://cursor.com/">cursor.com/</a>'
    TabOrder = 5
    OnLinkClick = HomePageLinkClick
  end
  object hkCursorShortcut: THotKey
    Left = 94
    Top = 105
    Width = 105
    Height = 23
    HotKey = 0
    Modifiers = []
    TabOrder = 6
  end
  object btnCursorClearShortcut: TButton
    Left = 205
    Top = 103
    Width = 44
    Height = 25
    Caption = 'Clear'
    TabOrder = 7
    OnClick = BuiltInClearShortcutClick
  end
  object btnCursorAdvanced: TButton
    Left = 255
    Top = 103
    Width = 130
    Height = 25
    Caption = 'Advanced Settings...'
    TabOrder = 8
    OnClick = BuiltInAdvancedSettingsClick
  end
  object chkWindsurfEnabled: TCheckBox
    Left = 16
    Top = 138
    Width = 121
    Height = 17
    Caption = 'Windsurf'
    TabOrder = 8
  end
  object lnkWindsurfHome: TLinkLabel
    Left = 152
    Top = 138
    Width = 113
    Height = 19
    Caption = '<a href="https://windsurf.com/editor">windsurf.com/editor</a>'
    TabOrder = 9
    OnLinkClick = HomePageLinkClick
  end
  object hkWindsurfShortcut: THotKey
    Left = 94
    Top = 163
    Width = 105
    Height = 23
    HotKey = 0
    Modifiers = []
    TabOrder = 10
  end
  object btnWindsurfClearShortcut: TButton
    Left = 205
    Top = 161
    Width = 44
    Height = 25
    Caption = 'Clear'
    TabOrder = 11
    OnClick = BuiltInClearShortcutClick
  end
  object btnWindsurfAdvanced: TButton
    Left = 255
    Top = 161
    Width = 130
    Height = 25
    Caption = 'Advanced Settings...'
    TabOrder = 12
    OnClick = BuiltInAdvancedSettingsClick
  end
  object chkTraeEnabled: TCheckBox
    Left = 16
    Top = 196
    Width = 121
    Height = 17
    Caption = 'TRAE'
    TabOrder = 12
  end
  object lnkTraeHome: TLinkLabel
    Left = 152
    Top = 196
    Width = 71
    Height = 19
    Caption = '<a href="https://www.trae.ai/">www.trae.ai/</a>'
    TabOrder = 13
    OnLinkClick = HomePageLinkClick
  end
  object hkTraeShortcut: THotKey
    Left = 94
    Top = 221
    Width = 105
    Height = 23
    HotKey = 0
    Modifiers = []
    TabOrder = 14
  end
  object btnTraeClearShortcut: TButton
    Left = 205
    Top = 219
    Width = 44
    Height = 25
    Caption = 'Clear'
    TabOrder = 15
    OnClick = BuiltInClearShortcutClick
  end
  object btnTraeAdvanced: TButton
    Left = 255
    Top = 219
    Width = 130
    Height = 25
    Caption = 'Advanced Settings...'
    TabOrder = 16
    OnClick = BuiltInAdvancedSettingsClick
  end
  object chkVSCodiumEnabled: TCheckBox
    Left = 16
    Top = 254
    Width = 121
    Height = 17
    Caption = 'VSCodium'
    TabOrder = 16
  end
  object lnkVSCodiumHome: TLinkLabel
    Left = 152
    Top = 254
    Width = 88
    Height = 19
    Caption = '<a href="https://vscodium.com/">vscodium.com/</a>'
    TabOrder = 17
    OnLinkClick = HomePageLinkClick
  end
  object hkVSCodiumShortcut: THotKey
    Left = 94
    Top = 279
    Width = 105
    Height = 23
    HotKey = 0
    Modifiers = []
    TabOrder = 18
  end
  object btnVSCodiumClearShortcut: TButton
    Left = 205
    Top = 277
    Width = 44
    Height = 25
    Caption = 'Clear'
    TabOrder = 19
    OnClick = BuiltInClearShortcutClick
  end
  object btnVSCodiumAdvanced: TButton
    Left = 255
    Top = 277
    Width = 130
    Height = 25
    Caption = 'Advanced Settings...'
    TabOrder = 20
    OnClick = BuiltInAdvancedSettingsClick
  end
  object sbCustomEditors: TScrollBox
    Left = 16
    Top = 352
    Width = 580
    Height = 116
    TabOrder = 21
  end
  object btnAddCustomEditor: TButton
    Left = 426
    Top = 474
    Width = 170
    Height = 25
    Caption = 'Add Custom Editor...'
    TabOrder = 22
    OnClick = btnAddCustomEditorClick
  end
  object lnkProjectHome: TLinkLabel
    Left = 16
    Top = 478
    Width = 162
    Height = 19
    Caption =
      '<a href="https://github.com/csm101/EditInVsCodeDelphiPlugin">Pro' +
      'ject home page on GitHub</a>'
    TabOrder = 23
    OnLinkClick = HomePageLinkClick
  end
end
