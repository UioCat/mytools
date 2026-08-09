# Super Right-Click Debuggable Design

## References

- uTools Super Panel user guide: https://www.u-tools.cn/docs/guide/uTools-super-panel.html
- uTools `plugin.json` command matching: https://www.u-tools.cn/docs/developer/information/plugin-json.html

The public uTools design is a "super panel" rather than a single hard-coded
right-click action. On macOS the default trigger is long right-click. The panel
then handles selected data and lets commands match by data type, such as text,
image, files, or the active window.

## Current Diagnosis

The previous MacTools implementation had two architectural problems:

1. Launch-time permission requests.
   `startSuperRightClickMonitor()` called `requestSuperRightClickPermissions()`,
   which can call macOS prompt APIs on every app start or activation. Permission
   prompts must only be triggered by an explicit user action.

2. Ambiguous capture failures.
   When selected text capture failed, the fallback could read old pasteboard
   content and classify it as the current right-click payload. That made a
   failed text capture look like an image or unknown payload.

## Target Pipeline

The feature should be split into observable stages:

1. Trigger Detector
   - Primary: `CGEvent.tapCreate` for right mouse down/up.
   - Debug fallback: `NSEvent.addGlobalMonitorForEvents`.
   - Output: `rightMouseDown`, `longPressTriggered`, `rightMouseUp`.

2. Permission Preflight
   - Read-only checks only during launch.
   - No prompt APIs on launch or app activation.
   - Prompt/open System Settings only from an explicit settings action.

3. Selection Capture
   - Strategy A: Accessibility selected text from focused element.
   - Strategy B: Copy shortcut, then require pasteboard `changeCount` to change.
   - Strategy C: Finder/file selection capture.
   - Strategy D: active window metadata.
   - Output: `text`, `files`, `image`, `window`, or empty payload with a reason.

4. Command Matcher
   - uTools-like command model:
     - text commands can match all text or regex.
     - image commands match image payloads.
     - file commands match extensions, count, or filename regex.
     - window commands match app name/title.
   - Output: ordered actions for the context panel.

5. Presenter
   - Text: translation action or text actions.
   - Files/folders/images: context action panel.
   - Empty payload: debug-visible no-op, not silent guessing.

## Diagnostic Events

Every right-click attempt should be traceable by one attempt id:

- `src.boot`: app id, code-signing requirement, build timestamp.
- `src.permission.preflight`: accessibility/input-monitoring/post-event status.
- `src.monitor.start`: `eventTap` or `globalFallback`.
- `src.event.down`: mouse location and frontmost app.
- `src.event.longPress`: threshold and elapsed time.
- `src.capture.axText`: success/failure reason.
- `src.capture.copyFallback`: pasteboard change before/after.
- `src.capture.result`: kind and byte/count summary, never secret content.
- `src.match.result`: action count and action ids.
- `src.presenter.result`: shown/skipped reason.

Logs should avoid writing selected text, API keys, or clipboard contents.

## Local Debug Flow

1. Build and launch:

   ```sh
   scripts/rebuild_and_run_app.sh
   ```

2. Inspect app identity and logs:

   ```sh
   scripts/diagnose_super_right_click.sh
   ```

3. Probe the trigger path:

   ```sh
   scripts/diagnose_super_right_click.sh --clear-log --probe
   ```

4. Interpret results:
   - No `right mouse down`: monitor layer failed.
   - Has `long press triggered`, but capture empty: selection capture layer failed.
   - Captures payload but action count is zero: matcher layer failed.
   - Actions exist but no UI: presenter layer failed.

## uTools-Like Feature Summary

The first MacTools implementation should match the visible behavior users expect
from uTools Super Panel before adding a configurable plugin marketplace.

1. Text selection
   - Long right-click on selected text opens a floating panel near the cursor.
   - Header summarizes the data source as `选中的文本 N 个`.
   - Preview area shows `原文` and, when available, `译文`.
   - Actions are ordered as quick utility commands:
     `复制译文`, `文本悬浮中转`, `插件应用市场搜一搜`, `百度一下`, `微软 Bing 搜索`.
   - Translation not configured or failed is shown inside the panel as a hint,
     not as a blocking alert.

2. URL selection
   - URL text uses the same panel and search/copy actions as regular text.
   - This mirrors uTools' command matching model where regex/text commands can
     process pasted or selected text.

3. Folder selection
   - Header uses the source application, normally `访达`, plus the folder name.
   - Actions match the expected file workflow:
     `复制当前路径`, `新建文件`, `终端中打开`, `Claude Code 打开`,
     `Claude Code 打开（跳过确认）`.
   - `新建文件` creates `Untitled.txt` and increments to `Untitled 2.txt` when
     needed.

4. File selection
   - Shows the file path and keeps `复制当前路径`, `在访达中显示`, and external
     app actions.

## Current Implementation Plan

1. Add a core `SuperPanelContent` model that maps classified payloads to visible
   headers, preview rows, and action ids.
2. Update `FileActionService` with deterministic file operations that can be
   tested without launching the UI.
3. Replace the text translation `NSAlert` with the same floating panel used for
   files and folders.
4. Render a legible uTools-style panel: stable width, white/glass background,
   clear primary text, preview rows, and large icon action rows.
5. Verify with both tests and a live screenshot of the app after a real long
   right-click; unit tests alone are not sufficient for completion.

## TCC Handling

Accessibility and Input Monitoring are tied to the app's code identity. Stable
MacTools releases therefore use the pinned anonymous `MacTools Release Signing`
certificate and the canonical `/Applications/MacTools.app` path. Development
builds use a separate `local.mactools.development` identity.

Recommended handling:

1. Maintainers run `scripts/rebuild_and_run_app.sh`. Stable mode accepts only the
   pinned certificate and installs `/Applications/MacTools.app`; it fails closed
   if the identity is missing or not trusted for code signing.

2. Contributors without that identity use
   `MACOS_SIGNING_MODE=development scripts/rebuild_and_run_app.sh`. The separate
   name and Bundle ID prevent development grants from becoming formal MacTools
   entries.

3. After migrating from an old ad-hoc identity, use Settings > Permissions >
   `整理旧权限记录`. The confirmed action scopes `tccutil reset All` to
   `local.mactools.mvp`; it never resets other applications.

4. Re-enable MacTools in:
   - System Settings > Privacy & Security > Accessibility
   - System Settings > Privacy & Security > Input Monitoring
   - Screen & System Audio Recording
   - Finder Automation when first requested

5. Run:

   ```sh
   scripts/diagnose_super_right_click.sh --clear-log --probe
   ```

   The expected healthy trigger path is `event tap installed` or global fallback
   plus `right mouse down` and `long press triggered`. The expected healthy
   capture path for selected text is `selection capture read selected text via
   accessibility` or a pasteboard change after copy fallback.

## Implementation Order

1. Stop launch-time permission prompts.
2. Keep stable local signing so TCC records do not bind to a changing cdhash.
3. Add structured attempt ids to current logs.
4. Replace hard-coded text/file branching with a command matcher.
5. Add a debug view in Settings that renders the latest attempt trace.
6. Add manual smoke tests to `docs/manual-verification.md`.
