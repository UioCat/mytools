# Privacy Scan

Date: 2026-07-14

## Scope

Scanned the current repository working tree under `.`, excluding `.git/`, `.worktrees/`, `.build/`, and `build/`.

## Result

- No confirmed plaintext API keys, access tokens, private keys, passwords, or live translation credentials were found.
- The Bailian translation provider uses user-supplied API keys at runtime. Source and tests only contain placeholder values such as `sk-test-key`.
- Runtime translation settings are saved outside the repository in Application Support; the settings file is written with owner-only `0600` permissions.
- The app stores runtime clipboard history, cached files, and logs outside the repository in Application Support. Sensitive directories use owner-only `0700` permissions and sensitive files use `0600` permissions.

## Findings

- `docs/superpowers/plans/2026-06-03-mac-tools-implementation.md` previously contained historical absolute user-home path examples. These were local-environment metadata rather than credentials.
- `Tests/MacToolsCoreTests/FileActionServiceTests.swift` contains synthetic absolute paths where the API behavior requires absolute-path fixtures. These are non-sensitive examples.
- Existing documentation under `docs/superpowers/` still references the earlier Baidu translation stub and Keychain guidance as historical plan/spec text.

## Mitigations Added

- Updated `.gitignore` to ignore editor state, SwiftPM/Xcode-derived state, local env/secret files, generated app bundles, logs, SQLite databases, SQLite sidecars, and clipboard cache directories.
- Added `AGENTS.md` privacy guidance requiring repository-relative project paths and explicit justification for exceptional absolute paths.
- Added owner-only permissions for settings, the clipboard database, clipboard cache files, runtime logs, and their sensitive directories.
