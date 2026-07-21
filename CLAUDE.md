# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language

All code, comments, identifiers, strings, documentation, and commit messages in this repository must be written in **English**. No Italian or other languages.

## What This Is

A RAD Studio (Delphi IDE) **design-time package** (`{$DESIGNONLY}`) that adds **Tools → Edit in <Editor>** menu commands. When triggered, it saves all open files, resolves the VS Code workspace (single project folder or a `.code-workspace` for project groups), launches the editor at the current file/line/column, and merges sensible Delphi defaults into `.vscode/settings.json`, `.vscode/extensions.json`, and `.vscode/launch.json`.

Despite the name, the plugin is **multi-editor**: it ships built-in profiles for VS Code, Cursor, Windsurf, Devin Desktop, TRAE, and VSCodium (all VS Code / Electron forks), plus user-defined custom profiles. Each enabled profile gets its own menu item and shortcut.

## Build & Install

No external build script. Open `EditInVSCode.dpk` (or `EditInVsCodeGrp.groupproj`) in RAD Studio, then **Build** and **Install** the package from the IDE.

- Target: design-time package (`{$DESIGNONLY}`) — no standalone executable
- Requires: `rtl`, `designide`; platform: Windows only (Win32/Win64)
- Cannot be built with `dcc32`/`dcc64` alone — needs the full Delphi package build tools
- No automated tests. Verification = install the package and exercise the menu commands manually.

After install, `Register` in `DGVisualStudioCodeIntegration.pas` runs automatically (called by the IDE package loader).

## Code Architecture

| Unit | Role |
|------|------|
| `DGVisualStudioCodeIntegration.pas` | `Register` entry point, menu items, and all core launch/workspace logic |
| `PluginSettings.pas` | `TEditorSettings` (one editor profile) + `TPluginSettings` (static class holding built-in + custom profiles, JSON persistence) |
| `FrmSettingsFrame.pas/.dfm` | IDE Options frame (Tools → Options → Third Party → Edit in VS Code); per-editor enable/shortcut rows + dynamically built custom-editor rows |
| `FrmEditorAdvancedSettings.pas/.dfm` | Modal dialog to edit one profile's command, window match, and arg templates |
| `FrmVSCodeLaunchError.pas/.dfm` | Error dialog with copyable diagnostics (command line, workdir, exit code, stdout/stderr) |
| `OSCmdLineExecutor.pas` | Win32 process launcher that captures stdout/stderr via pipes |

### Editor profile model (`TEditorSettings`)

Every editor (built-in or custom) is one `TEditorSettings` carrying: `Id`, `DisplayName`, `HomepageUrl`, `Enabled`, `Command`, `Shortcut`, window-match fields (`WindowClassName`, `WindowTitleSuffix`), and four launch-argument templates (`ReuseOpenArgs`, `ReuseGotoArgs`, `NewOpenArgs`, `NewGotoArgs`) plus `DelphiLspArgs`.

- Built-in defaults live in `TPluginSettings.CreateDefaultBuiltInEditorCopy` (keyed by `Id`); the canonical built-in ID list is in `AddDefaultBuiltInEditors`.
- Arg templates expand these placeholders (see `ExpandEditorArgumentTemplate`): `{workspacePath}`, `{filePath}`, `{gotoTarget}`, `{line}`, `{column}`. Reuse-vs-new and open-vs-goto are chosen at launch time in `ResolveEditorLaunchArgs`.
- `DelphiLspArgs` is appended only when the active project has a `.delphilsp.json` (triggers the LSP to reload settings).

### Key flows in `DGVisualStudioCodeIntegration.pas`

- **`Register`** — loads settings, wires `OnShortcutChanged` (live shortcut update) and `OnSettingsChanged` (`RebuildMainMenuItems`), registers the options page, then `TryRegisterMainMenuItems`. A `TTimer` retries menu registration because the Tools menu may not exist yet.
- **`TryRegisterMainMenuItems` / `RebuildMainMenuItems`** — add one menu item per *enabled* editor (caption `Edit in <DisplayName>`). If none enabled, add a single `Edit in VS Code Settings...` item that opens the options page.
- **`OpenCurrentFileInEditor(EditorSettings)`** — the main action. Gets current source file/line/col (falls back to the active project's `.dpr`/`.dpk` when no Delphi editor tab is active), warns about open child forms, saves all modules, resolves the workspace, regenerates `.vscode/launch.json`, then launches the editor on a **background thread**.
- **`GenerateOrUpdateVSCodeWorkspace` / `GenerateOrUpdateVSCodeFolderSettings`** — write the `.code-workspace` (project group) or `.vscode/settings.json` + `extensions.json` (single project). In workspace mode the `.code-workspace` also gets a `launch` section (one managed config for the Delphi active project, so F5 starts without a picker) and a `tasks` section (one `msbuild` build task per project, `isDefault` on the active one); competing per-folder `launch.json`/`tasks.json` plugin entries are removed so they do not hijack F5/Ctrl+Shift+B.
- **`GenerateOrUpdateLaunchJson`** — folder-mode launch/tasks generation for the active project. For a `.dpr` it emits a program `delphi-win64` config (exe + `.map` + `.rsm`); for a `.dpk` package it reads the **Host application** (Project Options > Debugger) and emits a BPL config (host exe as `program`, the package listed under `modules` with its `.map`/`.rsm`/`.dcp`). Output paths are resolved from the project's output options (`DCC_ExeOutput`/`DCC_BplOutput`/`DCC_DcpOutput`) plus the IDE package-output registry keys, with `$(BDS)`/`$(Platform)`/`$(Config)` macro expansion; source search paths come from `DCC_UnitSearchPath`, the IDE Win64 library search path, and `$(BDS)\source`. A matching `tasks.json` build task is written alongside.
- **`FindEditorWindow`** — `EnumWindows` + class-name/title-suffix match to reuse an already-open editor window for the target workspace instead of opening a new one.
- **`CheckAndHandleChildForms`** — detects inherited forms open in the IDE (RTTI via `INTAComponent`, walking `ClassParent`) that would not reload external changes; offers a `TTaskDialog` to close them.

### Shared workspace defaults (`vscode-workspace-defaults.json`)

Settings and extension recommendations are **not** hardcoded into the generated
output any more. They live in `vscode-workspace-defaults.json`, written next to
the `.groupproj` (workspace mode) or next to the project (folder mode):

- `LoadOrCreateWorkspaceDefaults(ADir)` reads it, and creates it from
  `BuildBuiltInWorkspaceSettings` + `BuildExtensionRecommendations` when absent.
  An existing but unparseable file is **never** overwritten — the built-in
  defaults are used in memory and the user's file is left alone.
- `ApplyStandardDelphiSettings(Settings, ActiveProject, ADefaults)` merges the
  file's `settings` through `MergeMissingInto` (recursive, add-only), then adds
  the one genuinely per-machine value, `delphiLsp.settingsFile`.
- `MergeExtensionRecommendations(ExtensionsObject, ADefaults)` takes the list
  from the file, falling back to the built-in list.

Rationale: the defaults file is the team's shared, version-controlled config;
the `.code-workspace` is generated per machine and should not be versioned.

### Checkout-independent paths

`MakePathWorkspaceRelative` / `MakeLaunchConfigPortable` rewrite `program`,
`sourceRoot`, `mapFile`, `rsmFile`, `sourceSearchPaths` and the `modules` paths
as `${workspaceFolder}/...` when they can be expressed relative to the workspace
root, so a generated configuration survives a different checkout location. The
relative form is derived, never assumed: another drive or no common root leaves
the path absolute. Applied only when the workspace has a **single** root —
`${workspaceFolder}` is ambiguous in a multi-root workspace, where VS Code wants
`${workspaceFolder:Name}`.

`CollectSourceSearchPaths` expands the full project macro set through
`ExpandProjectMacros` (not just the env/BDS ones) and roots relative entries on
the project directory. An entry that still contains `$(` is dropped: VS Code does
not understand Delphi macros and the debug adapter discards such an entry, so
emitting it would silently cost source resolution.

### JSON merge strategy (additive, never destructive)

All `.code-workspace` / `settings.json` / `extensions.json` / `launch.json` / `tasks.json` writes **preserve existing user keys** and only insert missing defaults. Plugin-owned entries (workspace folders, launch configs) are tagged `"managedBy": "editinvscode-delphi-plugin"` (`PLUGIN_MANAGED_BY_*` constants) so they can be rebuilt without touching user-added entries. When rebuilding, an old `delphi-win64` config is also replaced if it merely shares the generated config name (migrates pre-tagging entries). Build tasks are upserted by `label`. In workspace mode, per-folder `launch.json` plugin/scaffold `delphi-win64` configs and per-folder plugin build-task labels are removed (the `.code-workspace` `launch`/`tasks` sections are authoritative); user-authored per-folder configs are preserved. Files are written only when their content actually changes (`WriteTextIfChanged`).

### Settings persistence

Stored at `%APPDATA%\EditInVSCode\settings.json` (`TPluginSettings.Save`/`Load`), `SETTINGS_FORMAT_VERSION = 2`.

- Format v2 stores `builtInEditors` + `customEditors` arrays plus the global `generateDebuggerConfig` flag (default `true`; gates all `launch.json`/`tasks.json` + workspace launch/tasks generation — when `false`, the plugin writes only workspace/settings/extensions and leaves any existing debugger config untouched). Built-in profiles are matched back by `Id`; unknown IDs are ignored.
- **Legacy migration**: an old file with `vsCodeCommand`/`shortcut` keys (no `builtInEditors`) is read into the VS Code profile via `LoadLegacySettings`, then immediately re-saved in v2 format.
- `VSCodeCommand` / `Shortcut` class properties still exist but are thin shims over the built-in `vscode` profile (kept for back-compat).
- Options frame edits work on **clones** (`FBuiltInEditorDrafts` / `FCustomEditorDrafts`); they are applied back to `TPluginSettings` only on dialog Accept (`DialogClosed`), which then calls `Save` + the two notify callbacks.

## ToolsAPI Integration Points

`IOTAModuleServices` (enumerate/save modules, active project/module), `IOTAProjectGroup` (project group → workspace), `IOTAProject` + `IOTAProjectOptionsConfigurations140` (build config for launch.json), `IOTASourceEditor`/`IOTAEditView` (current file + cursor pos), `INTAServices` (`AddActionMenu`), `INTAEnvironmentOptionsServices` (options page), `INTAComponent` (form RTTI), `IOTAFormEditor` (child-form detection).

## Repo Automation (`.github/`)

GitHub Copilot prompt/instruction files mirror this plugin's conventions — consult them when relevant:

- `.github/copilot-instructions.md` — condensed architecture + style summary
- `.github/instructions/delphi-forms.instructions.md` — `.dfm` rules: form-via-DFM only, component-naming prefixes (`lbl`/`ed`/`btn`/`chk`/`cmb`/`hk`), layout conventions
- `.github/prompts/add-plugin-setting.prompt.md` — step-by-step workflow to add a new persisted setting end-to-end
- `.github/prompts/review-toolsapi-usage.prompt.md` — checklist for correct ToolsAPI nil-checks/lifetime/thread-safety

## Pitfalls

- **`{$DESIGNONLY}`**: never add `Application.Run` or anything assuming a standalone executable.
- **Thread safety**: the editor is launched on a background `TThread.CreateAnonymousThread`. ToolsAPI and VCL are **not** thread-safe — all needed data is captured into locals on the main thread *before* the thread starts, and any UI (error dialog) is marshalled back via `TThread.Queue`. Never call `BorlandIDEServices`, `ShowMessage`, or form access from that thread.
- **Menu registration race**: the `TTimer` retry in `Register` exists because the Tools menu may be empty at load. Menu items are added to the **top** of the Tools menu (the IDE deletes items under "Configure Tools..." when its dialog opens). Preserve this.
- **Non-ref-counted options object**: `TEditInVSCodeOptions._AddRef`/`_Release` return `-1`; lifetime is managed by the plugin via `FreeAndNil`, not reference counting. Do not store it in an interface variable that would release it.
- **Dynamic custom-editor rows**: `FrmSettingsFrame` builds custom-editor row controls in code (`RebuildCustomEditorRows`) — a deliberate exception to the form-via-DFM rule, justified by the runtime-variable row count. Row teardown/rebuild is deferred via a posted `WM_REBUILD_CUSTOM_EDITOR_ROWS` message to avoid freeing a control inside its own event handler.

## Code Style

Follow the full Delphi Style Guide in the user's global `CLAUDE.md`. Highlights enforced here:

- **CRLF** line endings for all `.pas`/`.dfm`/`.dpk`/`.dpr`/`.dproj`/`.inc` files
- Inline `var` preferred (Delphi 10.3+); never flag as non-idiomatic
- Early-exit / guard clauses; max 3 nesting levels; extract local functions otherwise
- `if … then` body always on its own line; no `begin/end` around a single statement; `begin` on the same line as `then`/`else`
- Max line length ~130 chars
