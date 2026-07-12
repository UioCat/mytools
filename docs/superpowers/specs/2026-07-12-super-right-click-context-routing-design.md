# Super Right-Click Context Routing Design

## Goal

Route super-right-click content according to the frontmost application and the selected Finder item:

- A non-Finder application with no selected text or supported content shows only the window-layout list.
- Finder with no selected item shows directory actions for the active Finder location, followed by the window-layout list.
- A selected folder uses the same directory actions.
- A selected file or image file shows only copy-file-path and the window-layout list.

## Behavior Matrix

| Context | Primary actions | Window layout |
| --- | --- | --- |
| Selected text or URL | Existing translation/text actions | Hidden |
| Non-Finder app with no supported selection | None | Shown |
| Finder with no selected item | New file, copy current path, open in Terminal | Shown |
| Selected folder | New file, copy current path, open in Terminal | Shown |
| Selected file or image file | Copy file path | Shown |

## Source Application Context

Replace the source-app-name-only handoff with a `SuperRightClickSourceApplication` value containing localized name, bundle identifier, and process identifier. The bundle identifier `com.apple.finder` is the authoritative Finder check; localized names such as `Finder` or `访达` are presentation only.

`SuperRightClickMonitor` captures this value at long-press time. `SuperRightClickService` continues classifying the selected clipboard payload and stores the source context in `SuperRightClickResult`.

## Presentation Routing

Add a testable `SuperRightClickPresentationRouter` in `MacToolsCore`:

- `.text` and `.url` route to the existing text panel.
- `.file`, `.folder`, and `.imageFile` route to file-system content.
- `.unknown` or `.imageData` from Finder route to the active Finder directory.
- `.unknown` or `.imageData` from other applications route to the window-layout-only panel.

This keeps AppKit-specific presentation code out of the routing rules.

## Finder Current Directory

Add a `FinderCurrentFolderResolving` protocol and an AppKit implementation that primarily reads the active Finder window's accessibility `AXDocument` URL using the captured Finder process identifier. When `AXDocument` has no usable value, request Automation authorization in a separate asynchronous step, then run a fixed Finder Apple Events query as a fallback. The first system authorization prompt is not subject to the normal query timeout. Denial or revocation safely degrades to the window-layout-only panel; once authorized, the normal Apple Events query remains bounded and fully reaps its child process after success, failure, timeout, or cancellation.

Only a successful accessibility lookup that reports an empty Finder windows array means Finder has no open window and may use the user's Desktop directory. Accessibility failures, invalid window data, and failed Apple Events fallback log only safe diagnostic reasons and show the window-layout-only panel. Never fall back to stale clipboard content.

Finder-background presentation is coordinated as latest-only work on the main actor. A newer Finder request replaces the older generation, while any selected text, selected file-system item, or layout-only result cancels pending Finder resolution. A cancelled or superseded Finder result performs no presentation, including no layout-only fallback.

## Panel Content

Update `SuperPanelContent.fileSystem`:

- Folder actions, in order: `新建文件`, `复制当前路径`, `在终端打开`, then configured layout buttons.
- File and image-file actions: `复制文件路径`, then configured layout buttons.
- Remove Finder reveal and Claude Code actions from these super-right-click contexts.

Add `ContextPanelController.showWindowLayoutOnly()` for empty non-Finder selections and Finder-path failures. Existing action execution methods remain reusable.

## Error Handling

- Finder path resolution failure degrades to the layout-only panel and emits a diagnostic log.
- Missing or invalid file paths continue using existing `FileActionService` errors.
- Empty window-layout configuration still shows the layout panel header without fabricating actions.

## Testing and Verification

- TDD tests for source context and presentation routing.
- Tests for Finder URL parsing and Desktop fallback through injected accessibility values.
- Update content tests for exact folder/file action order and titles.
- Preserve text-action tests proving no layout actions appear for selected text.
- Run focused tests, full `swift test`, privacy scan, and `scripts/rebuild_and_run_app.sh`.
- Visually inspect text, Finder background, folder, and file panels over light and dark backgrounds, including the no-gray-edge rule in `AGENTS.md`.
