---
description: "Review a Delphi unit for correct ToolsAPI usage: nil checks after interface queries, Supports calls, lifetime management, and thread safety."
argument-hint: "Unit to review (e.g. DGVisualStudioCodeIntegration.pas)"
agent: "agent"
---

Review the Delphi unit `$ARGS` for correct use of the RAD Studio ToolsAPI.

Check each of the following areas and report findings grouped by category.
For each issue found, cite the **procedure or function name** (not a line number) and explain the problem and the fix.

## 1. Nil checks after interface queries

- Every `BorlandIDEServices as IXxx` cast must be followed by a nil check before use, OR the cast itself must be wrapped in error handling.
- Every `Supports(obj, IXxx, result)` must check if result is non-nil before use.
- Look for implicit assumptions that `GetActiveProject`, `CurrentModule`, `GetEditView(0)`, etc. are non-nil.

## 2. `Supports` vs hard cast

- `as` on an interface type raises `EIntfCastError` if not supported; use `Supports` when the interface may not be present.
- Flag any `obj as IXxx` pattern where `obj` might not implement `IXxx` at runtime.

## 3. Lifetime management

- Interfaces obtained from ToolsAPI are reference-counted; do not store them in class fields unless you understand the lifetime implications with the IDE's object model.
- Flag objects that override `_AddRef`/`_Release` to return `-1` — verify they are **not** stored as interface variables (which would try to release them).
- Confirm `TEditInVSCodeOptions` is freed explicitly (not via ref count) before the package is unloaded.

## 4. Thread safety

- VCL and ToolsAPI calls must happen on the main thread only.
- If VS Code is launched on a background thread (e.g. via `TThread.CreateAnonymousThread`), flag any ToolsAPI or VCL call inside that thread — including `ShowMessage`, `BorlandIDEServices`, form access.

## 5. Menu/timer registration safety

- Confirm that the menu item is not added directly in `Register` if the Tools menu may not yet exist — the `TTimer` retry pattern must be preserved.
- Flag direct `AddActionMenu` calls outside a timer or equivalent deferred mechanism.

## Output format

For each finding:

```
[CATEGORY] ProcedureName — <short description of the problem>
  Fix: <concrete suggestion>
```

If no issues are found in a category, write `[CATEGORY] OK`.

Finally, provide a **Summary** section with a risk rating (Low / Medium / High) and the top 1-3 actions to take.
