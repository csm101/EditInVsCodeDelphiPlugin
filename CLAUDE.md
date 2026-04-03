# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language

All code, comments, identifiers, strings, documentation, and commit messages in this repository must be written in **English**. No Italian or other languages.

## What This Is

A RAD Studio (Delphi IDE) plugin that adds a **Tools → Edit in Visual Studio Code** menu command. When triggered, it saves all open files, determines the appropriate VS Code workspace (single project folder or a `.code-workspace` for project groups), then launches VS Code at the current file/line/column. It also merges sensible Delphi defaults into `.vscode/settings.json` and `.vscode/extensions.json`.

## Build & Install

Open `EditInVSCode.dpk` (or `EditInVsCodeGrp.groupproj`) in RAD Studio, build and install the package. There is no external build script.

- Target: RAD Studio design-time package (`{$DESIGNONLY}`)
- Requires: `rtl`, `designide`
- Platform: Windows only (Win32/Win64)

After installing, the plugin registers itself via `Register` in `DGVisualStudioCodeIntegration.pas`, which is called automatically by the IDE package loader.

## Code Architecture

```
DGVisualStudioCodeIntegration.pas   Main plugin unit — IDE registration, menu, all core logic
PluginSettings.pas                  Class-based persistent settings (JSON in %APPDATA%\EditInVSCode\settings.json)
FrmSettingsFrame.pas/.dfm           IDE Options frame shown under Tools→Options→Third Party→Edit in VS Code
FrmVSCodeLaunchError.pas/.dfm       Error dialog shown when the VS Code launch fails (copyable details)
OSCmdLineExecutor.pas               Utility: launches a process and captures stdout/stderr via Win32 pipes
EditInVSCode.dpk                    Package declaration
```

### Key flows in `DGVisualStudioCodeIntegration.pas`

- **`Register`** — entry point called by the IDE. Loads settings, registers the `TEditInVSCodeOptions` options page, and adds the menu item (with a timer retry if the Tools menu is not yet ready).
- **`OpenCurrentFileInVisualStudioCode`** — main action: validates the active editor, checks for open child forms, saves all modules, resolves the workspace path, then spawns a background thread to call VS Code via `cmd /c code ...`.
- **`GenerateOrUpdateVSCodeWorkspace`** / **`GenerateOrUpdateVSCodeFolderSettings`** — create or merge-update the `.code-workspace` or `.vscode/settings.json` + `.vscode/extensions.json` files. Existing user keys are preserved; only missing defaults are added. Plugin-managed workspace folders are tagged with `managedBy: "editinvscode-delphi-plugin"` so they can be rebuilt without destroying user-added folders.
- **`FindVSCodeWindow`** — uses `EnumWindows` + window title matching to find an already-open VS Code instance for the target workspace, to reuse it instead of opening a new window.
- **`CheckAndHandleChildForms`** — detects inherited forms open in the IDE (via RTTI through `INTAComponent`) that would not reload changes, and shows a `TTaskDialog` offering to close them automatically.

### Settings

`TPluginSettings` (class with class vars) holds two values:
- `VSCodeCommand` (default: `code`) — the executable or full path to VS Code
- `Shortcut` (default: `Ctrl+\`) — the keyboard shortcut for the menu item

Settings are stored as JSON at `%APPDATA%\EditInVSCode\settings.json`. Changes made in the IDE Options dialog are applied live to the menu shortcut without requiring an IDE restart (via `OnShortcutChanged` callback).

## ToolsAPI Integration Points

- `IOTAModuleServices` — enumerate/save open modules, get active project/module
- `IOTAProjectGroup` — detect and enumerate projects in a group
- `INTAServices` — add menu item to the Tools menu (`AddActionMenu`)
- `INTAEnvironmentOptionsServices` — register/unregister the options page
- `INTAComponent` — access the live `TComponent` for form inheritance checks (avoids file parsing)
- `IOTAFormEditor` — detect open form designers for the child-form warning
