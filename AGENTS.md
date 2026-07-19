# AGENTS.md

## Project Overview

MacTools is a Swift Package Manager macOS 26+ menu bar app. Its implemented features are clipboard history, Bailian translation, super right-click actions, region screenshots and screen recording, window layouts, settings, and permission diagnostics. The app runs with accessory activation policy and does not show a Dock icon by default.

## Repository Layout

| Path | Ownership |
| --- | --- |
| `Package.swift` | SwiftPM definition for the `MacTools` executable and `MacToolsCore` library; the external dependency is GRDB.swift |
| `Sources/MacTools` | AppKit entry point, runtime dependency wiring, menu bar, panels, Finder integration, global right-click monitoring, and ScreenCaptureKit implementation |
| `Sources/MacTools/App/ScreenCapture` | Selection overlay, screenshot editor, still capture, MP4 recorder, and recording controls |
| `Sources/MacToolsCore` | Reusable models, services, state machines, persistence, settings, permissions, translation, window-layout logic, screenshot rendering, and SwiftUI views |
| `Tests/MacToolsCoreTests` | Focused unit tests and UI decision/snapshot helpers |
| `scripts/package_app.sh` | Release build, local `.app` assembly, and trusted or ad-hoc signing |
| `scripts/rebuild_and_run_app.sh` | Rebuild, replace the running app, and launch `build/MacTools.app` |
| `scripts/diagnose_super_right_click.sh` | Inspect the packaged app, TCC state, process state, event probe, and `debug.log` |
| `docs/manual-verification.md` | Manual macOS smoke tests for UI, permissions, Finder, capture, and runtime behavior |

## Architecture Boundaries

- Keep AppKit and operating-system integration in `Sources/MacTools/App`; keep reusable behavior and state in `MacToolsCore`.
- Prefer SwiftPM-native changes. Do not add an Xcode project merely to configure build behavior already expressible in `Package.swift` or scripts.
- Inject pasteboard, workspace, event posting, permissions, translation HTTP, file system, clock, and capture services when logic must be testable.
- Preserve the observable super-right-click stages: event detection, permission preflight, selection/Finder resolution, classification, action construction, and panel presentation.
- Treat settings and hot keys as one runtime contract: saving settings must update the relevant service without requiring an app restart.

## Current Product Contracts

| Area | Contract to preserve |
| --- | --- |
| Tool hot keys | Defaults are `Option+Space` settings, `Option+1` clipboard, `Option+2` translation, and `Option+3` screen capture; all are configurable |
| Clipboard | SQLite metadata plus external file cache; favorites survive “clear non-favorites”; default history limit is 500 and default cache limit is 1024 MB |
| Translation | Live provider is Aliyun Bailian, provider ID `bailian`, model `qwen-mt-turbo`, using the DashScope OpenAI-compatible endpoint |
| Super right-click | Short press preserves the system menu; long press threshold is configurable at 250, 300, or 350 ms |
| Screen capture | User-dragged region only; screenshot copies annotated PNG; recording writes video-only H.264 MP4 to Downloads |
| Window layout | Eight built-in modes can be shown/hidden and assigned one or more shortcuts; application requires Accessibility access to move another app's window |

## Commands

```sh
# Focused test while iterating
swift test --filter TestCaseName

# Full unit suite
swift test

# Development launch
swift run MacTools

# Rebuild, sign, and launch the app bundle
scripts/rebuild_and_run_app.sh

# Build/sign only
scripts/package_app.sh

# Super right-click diagnostics
scripts/diagnose_super_right_click.sh
```

Use the packaged app for Finder Automation, TCC identity, signing, screenshot/recording, or release-behavior checks. `swift run MacTools` is not evidence for those behaviors.

## Working Tree Safety

- Run `git status --short` before editing. Existing modified and untracked files are user work unless the task clearly owns them.
- Make the smallest behavior-preserving change and follow nearby patterns. Do not reformat or rewrite unrelated files.
- Use repository-relative paths for every project file reference. Absolute paths are allowed only when an operating-system/API contract or an explicit task requirement makes them necessary; document the reason and never embed a real user-home path.
- Generated `.build/`, `build/`, app bundles, local logs, SQLite files, clipboard caches, recordings, and editor metadata are not source artifacts.
- Do not use destructive Git commands to remove unrelated work.

## 提交与推送

- 每次完成源代码、测试、脚本或文档修改并通过必要验证后，必须主动创建 Git commit 并 push 到对应远程分支，不等待用户再次提醒。
- Git commit 信息，以及面向用户的提交、合并和推送结果说明，必须使用中文。
- 提交和推送前必须确认改动范围、验证结果与目标分支，不得夹带无关的用户改动。

## Coding Guidance

- Add or update focused tests in `Tests/MacToolsCoreTests` for behavior changes. Prefer deterministic helpers over tests that depend on live TCC state or the active desktop.
- Keep runtime UI text and permission behavior aligned with `docs/manual-verification.md` and update that checklist when user-visible behavior changes.
- Avoid blocking the main actor with Finder scripting, translation HTTP, capture startup, or file I/O. Preserve cancellation and stale-result protection in Finder resolution.
- Keep clipboard payload classification and persistence backward compatible. Database or settings schema changes require migration/default-decoding coverage.
- Do not hide hot-key registration failures by changing product defaults to unsupported keys; Carbon key support lives in `HotKeyService`.

## UI Visual Verification

After every UI change:

1. Run `scripts/rebuild_and_run_app.sh`.
2. Inspect every affected panel over contrasting light and dark backgrounds.
3. Exercise resizing, focus changes, outside-click dismissal, keyboard navigation, and the relevant permission state.

Any unintended gray outline, titlebar residue, rectangular system shadow, or backing layer outside the intended rounded Liquid Glass surface is a release blocker. For `NSPanel` surfaces, verify the AppKit style mask, `hasShadow`, transparency, and rounded backing-layer clipping instead of covering window chrome inside SwiftUI.

## Permissions And Runtime Verification

| Change area | Required evidence beyond unit tests |
| --- | --- |
| Super right-click or auto-paste | Packaged-app check with Accessibility and Input Monitoring; confirm short press still opens the system menu |
| Finder current-folder resolution | Packaged-app checks for granted, first-prompt, denied/revoked, timeout, cancellation, and stale-result cases |
| Window layout | Move the focused window on the active display through both panel actions and configured hot keys |
| Screenshot or recording | Screen Recording permission flow, region selection, cancel path, annotated clipboard PNG, playable MP4, and duplicate-session guard |
| Packaging or signing | Run `scripts/package_app.sh`, inspect/signature as relevant, and launch `build/MacTools.app` |

## Privacy And Secrets

- Never add credentials, Authorization headers, clipboard contents, user paths, recordings, or runtime logs to source, tests, fixtures, snapshots, or documentation.
- Current translation settings, including the Bailian API Key, are stored in `~/Library/Application Support/MacTools/settings.json` with `0600` permissions. Do not log or expose that value. Credential-storage work should migrate it to Keychain rather than introduce additional plaintext stores.
- Treat `Clipboard.sqlite`, `ClipboardCache/`, `settings.json`, `debug.log`, repository-local `log/`, and test fixtures containing clipboard-like content as sensitive user data.
- Use temporary directories in tests and repository-relative paths in documentation. Do not hard-code real absolute user paths.
- Before committing, scan source-controlled scope for likely secrets without printing local runtime data:

```sh
rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.worktrees/**' \
  --glob '!.build/**' \
  --glob '!build/**' \
  --glob '!log/**' \
  -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

Review matches contextually: API field names and placeholder test values are expected, real values are not.

## Verification Before Completion

- Documentation-only changes: inspect links, commands, paths, and `git diff --check`; run tests when the documentation claims or changes executable behavior.
- Core behavior changes: run the narrowest relevant test first, then `swift test` before claiming completion.
- UI, permission, Finder, capture, or packaging changes: add the applicable manual checks above; if they cannot be performed, state the exact unverified boundary and remaining risk.
- Do not claim success based only on compilation or a launched process. Verify the user-visible outcome described by the change.
