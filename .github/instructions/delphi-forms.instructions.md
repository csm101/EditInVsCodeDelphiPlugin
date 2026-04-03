---
description: "Use when creating or editing Delphi form files (.dfm). Covers form-via-DFM rules, component naming, layout, and anti-patterns for this plugin's design-time package."
applyTo: "**/*.dfm"
---

# Delphi Form Guidelines

## Form-via-DFM — Never create forms in code

All component properties and layout must live exclusively in the `.dfm` file.
Never instantiate or configure components in `.pas` code unless there is an explicit, documented reason (e.g. dynamic runtime count).

## Component naming

Follow the existing convention in this project:

| Widget type | Prefix | Example |
|-------------|--------|---------|
| `TLabel` | `lbl` | `lblVSCodeCommand` |
| `TEdit` | `ed` | `edVSCodeCommand` |
| `TButton` | `btn` | `btnBrowse` |
| `TCheckBox` | `chk` | `chkOpenInNewWindow` |
| `TComboBox` | `cmb` | `cmbLaunchMode` |
| `THotKey` | `hk` | `hkShortcut` |
| `TFrame` | `frm` | `FrmSettingsFrame` |

## Layout rules

- Place a descriptive `TLabel` immediately above each control.
- Use the `lblXxxHint` naming pattern for secondary hint labels below a control.
- Maintain consistent vertical spacing (≈ 8 px between groups, ≈ 4 px label-to-control gap).
- Do **not** hard-code `TabOrder`; let the IDE assign it top-to-bottom after saving.

## Frames inside the IDE Options dialog

`TFrmSettingsFrame` is a `TFrame`, **not** a `TForm`. Rules specific to this context:

- Do not set `Caption`, `BorderStyle`, or any `TForm`-only property.
- The frame is instantiated by the IDE — never call `TFrmSettingsFrame.Create` directly in production code.
- Controls are wired in `TEditInVSCodeOptions.FrameCreated` / `DialogClosed`; do not add `OnChange` wiring in the DFM.

## CRLF line endings

The `.dfm` file **must** use Windows CRLF line endings. Never save with LF-only endings.

## Anti-patterns

- Do **not** set `Visible := False` on a component in code to hide it — use DFM `Visible = False` instead.
- Do **not** create `TOpenDialog` or any dialog as a persistent component on the frame — always create and free them locally in the event handler.
- Do **not** duplicate property overrides in both DFM and code (e.g. setting `Caption` in both places).
