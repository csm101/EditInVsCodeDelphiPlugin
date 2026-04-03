# Project Guidelines — EditInVsCodeDelphiPlugin

RAD Studio (Delphi IDE) design-time package that adds **Tools → Edit in Visual Studio Code**.
See [README.md](../README.md) for end-user documentation and [CLAUDE.md](../CLAUDE.md) for full architecture details.

## Build & Install

No external build script. Open `EditInVSCode.dpk` (or `EditInVsCodeGrp.groupproj`) in RAD Studio,
then **Build** and **Install** the package from the IDE.

- Target: design-time package (`{$DESIGNONLY}`) — no standalone executable
- Requires: `rtl`, `designide`; platform: Windows only (Win32/Win64)
- Cannot be built with `dcc32`/`dcc64` alone — requires the full Delphi package build tools

Testing requires installing the built package in RAD Studio and exercising the menu command manually
(no automated test suite exists).

## Code Style

Follow the [Delphi Style Guide in CLAUDE.md](../CLAUDE.md) for every file touched:

- **Inline `var`** declarations are preferred (Delphi 10.3+); never flag them as non-idiomatic
- **Early exit / guard clauses** to reduce nesting — never exceed 3 levels of nesting
- **CRLF line endings** for all `.pas`, `.dfm`, `.dpk`, `.dproj` files
- `if … then` body always on its own line; no `begin/end` for single statements
- Maximum line length: 130 characters

## Architecture & Key Conventions

### Component map

| Unit | Role |
|------|------|
| `DGVisualStudioCodeIntegration.pas` | IDE registration, menu item, all core logic |
| `PluginSettings.pas` | `TPluginSettings` — static class (class vars) for persistent settings |
| `FrmSettingsFrame.pas/.dfm` | IDE Options frame — Tools → Options → Third Party → Edit in VS Code |
| `FrmVSCodeLaunchError.pas/.dfm` | Error dialog with copyable diagnostics |
| `OSCmdLineExecutor.pas` | Win32 process launcher that captures stdout/stderr via pipes |

### ToolsAPI interfaces used

`IOTAModuleServices`, `IOTAProjectGroup`, `IOTAProject`, `IOTASourceEditor`, `IOTAEditView`,
`INTAServices` (menu), `INTAEnvironmentOptionsServices` (options page), `INTAComponent` (form RTTI),
`IOTAFormEditor` (child-form detection).

### JSON merge strategy

All `.code-workspace` / `.vscode/settings.json` / `.vscode/extensions.json` writes are **additive**:
existing user keys are never overwritten — only missing defaults are inserted.
Plugin-managed workspace folders are tagged with `"managedBy": "editinvscode-delphi-plugin"` so
they can be rebuilt without destroying user-added folders.

### Settings

Stored at `%APPDATA%\EditInVSCode\settings.json`.
Access only via `TPluginSettings` class properties (`VSCodeCommand`, `Shortcut`).
The `OnShortcutChanged` callback allows live shortcut updates without an IDE restart.

## Potential Pitfalls

- **`{$DESIGNONLY}`**: never add `Application.Run`, GUI forms instantiated outside the IDE lifecycle,
  or anything that assumes a standalone executable context.
- **Menu registration race**: adding the menu item uses a `TTimer` retry because the Tools menu may
  not exist when `Register` is first called. Do not break this pattern.
- **Non-ref-counted object**: `TEditInVSCodeOptions` overrides `_AddRef`/`_Release` to return `-1`
  (lifetime managed by the plugin, not by reference counting). Preserve this when editing the options page.
- **Thread safety**: VS Code is launched from a background thread
  (`OpenCurrentFileInVisualStudioCode`); never access VCL/ToolsAPI from that thread.
