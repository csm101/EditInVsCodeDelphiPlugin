# Edit in Visual Studio Code (Delphi Plugin)

If you want to use GitHub Copilot or the Delphi LSP extension while working on Delphi code, this plugin makes the RAD Studio to Visual Studio Code round-trip much smoother.

This plugin adds a "Tools->Edit in Visual Studio Code" command to RAD Studio.

Terminology note:

1. "Visual Studio Code" (or "VS Code") is the external editor used by this plugin.
2. "RAD Studio" (Delphi IDE) is the Embarcadero IDE where this plugin is installed.

In this document, "Visual Studio" always means "Visual Studio Code".

When you use that command, the plugin will:

1. Save all modified files currently open in the IDE.
2. Open the current Delphi source file in Visual Studio Code at the exact line and column you were editing in RAD Studio.
3. Reuse an existing Visual Studio Code window when possible, instead of opening duplicate editors for the same workspace.

The plugin settings are available in Delphi under Tools->Options->Third Party->Edit in VS Code.

## What's New in the Latest Version

The latest version adds several practical improvements:

1. Full Project Group support: when a Delphi project group is active, the plugin now generates and opens an equivalent VS Code workspace for the whole group, not just a single project folder.
2. Configurable launch behavior: both the keyboard shortcut and the VS Code launch command are now configurable from Tools->Options->Third Party->Edit in VS Code.
3. Smarter instance reuse: the plugin now searches for a VS Code window already associated with the current workspace before reusing it, instead of reusing a generic instance.
4. Non-destructive settings generation: VS Code settings and extension recommendations are merged instead of overwritten, preserving user customizations.
5. Automatic Delphi workspace cleanup defaults: the plugin configures `files.exclude` with common Delphi output/history patterns (`**/Debug`, `**/Release`, `**/Win32/Debug`, `**/Win32/Release`, `**/Win64/Debug`, `**/Win64/Release`, `**/__recovery`, `**/__history`, `**/.#*`, `**/*.rc`, `**/*.res`, `**/*.RES`, `**/*.bak`, `**/*.BAK`).
6. Better launch diagnostics: startup failures now show a detailed, copyable error dialog with command line, working directory, exit code, stdout, and stderr.
7. Better Delphi form workflow support: the plugin warns when child forms are open and handles the most common IDE edge cases before switching to VS Code.

## Release Notes

### Added

1. Project Group-aware workflow with automatic generation/update of `.code-workspace` files.
2. Settings page integrated in Delphi Tools->Options under Third Party->Edit in VS Code.
3. Persistent plugin settings (`%APPDATA%\EditInVSCode\settings.json`) for launch command and shortcut.
4. Dedicated VS Code launch error dialog with copyable diagnostics.
5. Child form detection and warning dialog before opening files externally.
6. Automatic `files.exclude` defaults for common Delphi build/output/history artifacts (`Debug/Release`, `Win32/Win64`, `__recovery`, `__history`, `.rc/.res/.bak`, and temporary lock-like files).

### Changed

1. Menu command renamed to "Tools->Edit in Visual Studio Code" and aligned with settings naming.
2. VS Code window reuse strategy improved to target the window matching the current workspace.
3. VS Code configuration generation changed from overwrite to merge behavior for folders, settings, and recommendations.
4. Shortcut handling updated to reflect runtime setting changes without requiring IDE restart.

### Fixed

1. Fixed command line quoting issues when the configured VS Code executable path contains spaces.
2. Improved user-facing error messages when the active tab is not a Delphi source editor.
3. Improved stability around startup/registration flow by avoiding asynchronous menu registration races.

## Why Use Visual Studio Code for Delphi?

1. **Copilot with Delphi**: this is the main reason the plugin exists. If you install the Copilot extension in Visual Studio Code, it works very well with Delphi code.
2. Visual Studio Code is a much more capable text editor than the one built into RAD Studio for many editing tasks, for example multi-cursor editing and extension-based workflows.

## Another Delphi Plugin of Mine You Might Want to Try

Also take a look at [DFMTextStabilizer](https://github.com/csm101/DFMTextStabilizer).
It improves how Delphi serializes text `.dfm` files, making them much more readable and significantly more merge/diff friendly in team workflows.
In practice, this means fewer noisy conflicts, cleaner Git history, and better handling of non-ASCII text in forms.

## Some Cool Things You Can Do with Copilot

Copilot is an AI assistant specialized in programming. Running it inside Visual Studio Code means it can understand your code, your comments, and the surrounding context, then suggest useful completions and edits.

Here are some screenshots of Copilot suggesting Delphi code.

Here it completes the `TDaysOfTheWeek` enum. The suggestion is the gray text: just press Tab to accept it.

![Delphi Programming TDaysOfTheWeek being auto-completed by Copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/62d3115c-4f08-4ad5-a8b5-a6e1238c8b0d)

Same for the `TLanguages` enum:

![Delphi Programming TLanguages being auto-completed by Copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/96be5322-b890-49fd-831f-dd2620e47e2f)

Here it suggests a whole function implementation:

![Whole Delphi Programming function implementation auto-completed by Copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/57f5c114-beaf-4e9d-bff1-608c1bbb1d6a)

You can also chat with Copilot about a selected portion of code and ask it to explain what it does:

![Copilot explaining Delphi Programming Code](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/d1c2526c-81f5-4420-99f5-cb4d682b14c1)

This is only a small sample. You can also ask Copilot to modify code with prompts such as "use meaningful variable names", "refactor this function into smaller local functions", "add comments", or "write XML documentation for this class".

## Copilot Chat and Agent Mode

With code completion, Copilot suggests text while you type in the editor.
With Copilot Chat, you write requests in plain language (for example "refactor this method", "explain this class", "add tests", or "apply this pattern to these files") and Copilot answers in the chat.

**Agent mode** is an extension of chat: instead of just answering with suggestions, Copilot can execute a complete coding task flow across the codebase.
You describe the target result, and Copilot can inspect files, propose concrete edits, apply changes, and iterate with your feedback.

In short:

1. You describe the objective in natural language.
2. Copilot analyzes the current codebase.
3. Copilot updates the relevant files.
4. You test, review, and ask for refinements.
5. Repeat until the feature is complete.

This new edition of the plugin was developed exactly this way.

All Delphi source changes since the previous commit were produced through chat-driven requests in Visual Studio Code. No manual edits were made directly in the Delphi source editor during this update cycle.

And if you are wondering: yes, even this paragraph was written by Copilot. The author simply asked Copilot in chat to add a section to this README.md file explaining what you can do with Copilot Chat and agent mode.

This is a practical example of using agent mode for full end-to-end maintenance:

1. feature implementation
2. refactoring
3. bug fixing
4. UX improvements
5. documentation updates

## How to Use This Plugin from Delphi

1. Download the source code from this repository.
2. Open the package project, build it, and install it.
3. Enable Delphi Code Insight in RAD Studio under Tools->Options->Editor->Language->Delphi->Code Insight.
   This is necessary for the Delphi LSP extension in Visual Studio Code to work correctly.

![How to use this plugin (Delphi side)](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/c254e016-c44a-40ba-afab-a8b5c6246089)

4. Optional: disable the confirmation prompts shown when Delphi detects that a file unchanged in the IDE has changed on disk.
   This makes switching back from Visual Studio Code to Delphi much smoother, as long as you do not have unsaved edits pending in the RAD Studio editor.

![Disable the confirmation requests](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/c0536311-dc6b-462a-a590-09ab5d715765)

## Install and Configure Visual Studio Code

1. Download and install Visual Studio Code from https://code.visualstudio.com/download.
2. Launch Visual Studio Code and install the DelphiLSP extension from the marketplace.

![Launch VSCode and install the DelphiLSP extension from its marketplace](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/d0a6bbf1-8a30-4aa7-bc3a-6c6d1b9a32f7)

You will also need the Copilot extensions:

![copilot extension](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/aa9473a4-ce94-4130-8007-845112bdf1d1)

## How to Enable Copilot

1. Create a GitHub account if you do not already have one.
2. Enable Copilot on your GitHub account by choosing a plan that fits your needs (for example Free, Pro, Business, or Enterprise, depending on current availability).
   You can manage this from your GitHub account settings under Copilot, or from the official Copilot pricing page.
   For individual developers, Copilot Pro is typically about 10 EUR/month (GitHub pricing is usually listed in USD, with local currency conversion by your payment method).
   In practical terms, Pro gives you unlimited usage of the included/basic models (which are capped in Copilot Free), plus access to more powerful reasoning models such as GPT-5.3-Codex, Claude Sonnet, and Gemini 2.5 Pro.
   Pro also includes a monthly bundle of premium requests, which is usually enough for regular daily use of chat and agent mode; those advanced reasoning models are not available in the Free plan.
3. Back in Visual Studio Code, sign in with Copilot.

![In Visual Studio Code, sign in with copilot](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/89ac2bba-b7a9-4be4-a57d-e4f082e20ced)

## Useful Visual Studio Code Configuration Tips

### Enable Auto Save in Visual Studio Code

This makes Visual Studio Code save changes automatically, so when you switch back to Delphi you will already find the updated file on disk. If you also disabled the reload prompt in Delphi as suggested above, the workflow becomes much smoother.

Just remember that Delphi does not auto-save when you switch from Delphi to Visual Studio Code unless you launch Visual Studio Code through the Tools->Edit in Visual Studio Code menu command.

This is easy to enable: just check the option in the File menu.

![check this option in the File menu](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/5ee10c81-3a23-4a09-832f-74d6453b5c7d)

### Enable File Encoding Auto-Detection

By default, Visual Studio Code opens source files as UTF-8. Many Delphi codebases still contain source files encoded with a local ANSI 8-bit code page.

The plugin now configures this automatically in the generated workspace/folder settings by setting `files.autoGuessEncoding` to `true` when the key is missing.

In other words, for projects opened through this plugin you usually do not need to enable "Auto Guess Encoding" manually.

If you prefer to manage this globally, you can still search for "Auto Guess Encoding" in the Visual Studio Code settings and enable it yourself.

![Search the "Auto Guess Encoding" under VSCode settings, and enable it](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/22c8a93a-e14d-4bf1-8031-a08f205d8526)

You can open the settings UI with Ctrl+, or by clicking the gear icon in the bottom-left corner of Visual Studio Code.

### Enable Ligatures and Install a Font That Supports Them

This is optional, but many people like it. With a ligature-supporting font such as Fira Code, typing ">=" can be rendered as "≥" and similar operator sequences are displayed more cleanly.

1. Install the font from https://github.com/tonsky/FiraCode.
2. Search for "Font Family" in Visual Studio Code settings and add `'Fira Code'` at the beginning of the comma-separated list.
3. Search for "ligatures" in the settings UI. Choose the option to edit `settings.json`, then add `"editor.fontLigatures": true` to your configuration.

![Enable "ligatures" and install a font that supports them](https://github.com/csm101/EditInVsCodeDelphiPlugin/assets/5736859/710b3e2c-0bc7-4aef-a334-c9a3edc30520)








































