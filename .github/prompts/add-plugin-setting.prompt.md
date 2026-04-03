---
description: "Guided workflow to add a new configurable setting to the plugin: PluginSettings class var, JSON serialization, IDE Options frame control, and usage site."
argument-hint: "Setting name and type, e.g. 'OpenInNewWindow: Boolean' or 'DefaultProfile: string'"
agent: "agent"
---

Add a new configurable setting to the EditInVSCode plugin.

**Setting to add:** `$ARGS`

Follow every step below in order. All edits must respect the code style in [CLAUDE.md](../../CLAUDE.md):
CRLF line endings, inline `var`, early-exit, max 3 nesting levels, no superfluous `begin/end`.

---

## Step 1 — Determine the type and default

Infer the Delphi type and a sensible default value from the setting name/description.
If ambiguous, state your assumption explicitly before proceeding.

---

## Step 2 — `PluginSettings.pas`: add the class var and property

1. Add a `DEFAULT_<SETTINGNAME>` constant near the existing defaults at the top of the file.
2. Add a `class var F<SettingName>: <Type>` in the `strict private` section of `TPluginSettings`.
3. Add a `class property <SettingName>: <Type> read F<SettingName> write F<SettingName>` in the `public` section.
4. In `class constructor TPluginSettings.Create`, initialise `F<SettingName>` from the new constant.
5. In `TPluginSettings.Load`, read the new JSON key in the same style as `vsCodeCommand` and `shortcut`.
6. In `TPluginSettings.Save`, write the new JSON key via `Root.AddPair`.

---

## Step 3 — `FrmSettingsFrame.dfm`: add the UI control

Design the control appropriate for the type:
- `Boolean` → `TCheckBox`
- `string` with path → `TEdit` + `TButton` (browse)
- `string` freeform → `TEdit`
- Enumeration → `TComboBox`

Place it below the existing controls in the frame, following the existing visual layout.
Add a descriptive `TLabel` above the control.
Use the same naming convention: `lbl<SettingName>`, `ed<SettingName>` / `chk<SettingName>` / `cmb<SettingName>`.

---

## Step 4 — `FrmSettingsFrame.pas`: wire up load and save

1. Declare the new control field in `TFrmSettingsFrame` (the DFM already generates it; confirm it is listed).
2. In `TEditInVSCodeOptions.FrameCreated`, populate the new control from `TPluginSettings.<SettingName>`.
3. In `TEditInVSCodeOptions.DialogClosed`, read the control value back into `TPluginSettings.<SettingName>` using the same guard-clause style as the existing `newCmd` check.
4. Call `TPluginSettings.Save` at the end of `DialogClosed` (it is already called — just ensure the new assignment happens before `Save`).

---

## Step 5 — Usage site in `DGVisualStudioCodeIntegration.pas`

Identify the function(s) in `DGVisualStudioCodeIntegration.pas` that should read the new setting.
Apply the setting value via `TPluginSettings.<SettingName>`.
Do not duplicate the logic — introduce a local helper function if the same conditional appears more than once.

---

## Step 6 — Verify

After all edits, confirm:
- [ ] `Load` reads the new key; missing key leaves the default intact
- [ ] `Save` writes the new key
- [ ] `FrameCreated` populates the control from settings
- [ ] `DialogClosed` (Accepted path) saves the control value back
- [ ] The new control is visible in the DFM and uses the correct naming convention
- [ ] No VCL/ToolsAPI calls added inside background threads
