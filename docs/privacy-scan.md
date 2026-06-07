# Privacy Scan

Date: 2026-06-05

## Scope

Scanned the current repository working tree under `/Users/hanxun/code/mytools`, excluding `.git/`, `.worktrees/`, `.build/`, and `build/`.

## Result

- No confirmed plaintext API keys, access tokens, private keys, passwords, or live translation credentials were found.
- The Bailian translation provider uses user-supplied API keys at runtime. Source and tests only contain placeholder values such as `sk-test-key`.
- Runtime translation settings are saved outside the repository in Application Support; the settings file is written with owner-only `0600` permissions.
- The app stores runtime clipboard history and cached file data outside the repository in Application Support. These files are sensitive user data and should not be copied into the repo.

## Findings

- `docs/superpowers/plans/2026-06-03-mac-tools-implementation.md` contains historical absolute `/Users/<name>/...` path examples. These are not credentials, but they are local-environment metadata.
- `Tests/MacToolsCoreTests/FileActionServiceTests.swift` contains sample `/Users/example/...` paths used as test fixtures. These are non-sensitive examples.
- Existing documentation under `docs/superpowers/` still references the earlier Baidu translation stub and Keychain guidance as historical plan/spec text.

## Mitigations Added

- Updated `.gitignore` to ignore editor state, SwiftPM/Xcode-derived state, local env/secret files, generated app bundles, SQLite databases, and clipboard cache directories.
- Added `AGENTS.md` privacy guidance requiring future agents to avoid plaintext credentials, runtime clipboard data, and hard-coded user paths.
- Added `SettingsStore` owner-only file permissions for local settings that can contain the Bailian API Key.

## Suggested Follow-Up

- Consider replacing historical absolute paths in `docs/superpowers/plans/2026-06-03-mac-tools-implementation.md` with repo-relative paths if that plan is still meant to be shared.
- If local-file credential storage is no longer required, consider migrating the Bailian API Key to Keychain.
