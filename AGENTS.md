# AGENTS.md

## Project Overview

MacTools is a Swift Package Manager macOS menu bar app. It provides clipboard history, file/folder quick actions, super right-click handling, settings, permission checks, and a stubbed Baidu translation provider.

## Repository Layout

- `Package.swift`: SwiftPM package definition for the `MacTools` executable and `MacToolsCore` library.
- `Sources/MacTools`: AppKit application entry point, app delegate, menu bar controller, panel wiring, and runtime views.
- `Sources/MacToolsCore`: Core services, models, persistence, settings, permissions, right-click flow, paste/file actions, translation SPI, and SwiftUI views.
- `Tests/MacToolsCoreTests`: Unit tests for core behavior and UI helper decisions.
- `scripts/package_app.sh`: Builds and signs a local `build/MacTools.app` bundle.
- `docs/manual-verification.md`: Manual smoke-test checklist for macOS behavior that unit tests cannot fully cover.

## Commands

- Run tests: `swift test`
- Run the app: `swift run MacTools`
- Build release app bundle: `scripts/package_app.sh`

## Coding Guidance

- Prefer SwiftPM-native changes and keep `MacToolsCore` reusable outside the AppKit shell.
- Keep AppKit integration in `Sources/MacTools/App` and shared logic in `Sources/MacToolsCore`.
- Add or update focused tests in `Tests/MacToolsCoreTests` for behavior changes.
- Do not rewrite user work in an existing dirty worktree. Inspect `git status --short` before editing.
- Use dependency injection for system services such as pasteboard, workspace opening, event posting, permissions, and translation providers.
- Keep runtime UI text and permission behavior aligned with `docs/manual-verification.md`.

## Privacy And Secrets

- Do not commit `.idea/`, `*.iml`, `.env*`, local credentials, generated app bundles, SQLite files, or clipboard caches.
- Clipboard history and cached files are user data. Treat `Clipboard.sqlite`, `ClipboardCache/`, and test fixtures containing clipboard-like content as sensitive.
- Translation credentials must not be stored in plaintext settings or source files. When the live provider is implemented, store credentials in Keychain.
- Avoid hard-coded absolute user paths. Use temporary directories in tests and relative paths in docs where possible.
- Before committing, run a quick sensitive-content scan such as:

```sh
rg -n --hidden --glob '!.git/**' --glob '!.worktrees/**' --glob '!.build/**' --glob '!build/**' -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

## Verification

- For code changes, prefer `swift test`.
- For app behavior changes, also run the relevant steps in `docs/manual-verification.md`.
- For packaging changes, run `scripts/package_app.sh` and launch `build/MacTools.app`.
