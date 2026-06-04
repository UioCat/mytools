# Privacy Scan

Date: 2026-06-04

## Scope

Scanned the current repository working tree under `/Users/hanxun/code/mytools`, excluding `.git/`, `.worktrees/`, `.build/`, and `build/`.

## Result

- No confirmed plaintext API keys, access tokens, private keys, passwords, or live translation credentials were found.
- The Baidu translation provider is currently wired with `configuration: nil`; tests use placeholder values only.
- The app stores runtime clipboard history and cached file data outside the repository in Application Support. These files are sensitive user data and should not be copied into the repo.

## Findings

- `docs/superpowers/plans/2026-06-03-mac-tools-implementation.md` contains historical absolute `/Users/<name>/...` path examples. These are not credentials, but they are local-environment metadata.
- `Tests/MacToolsCoreTests/FileActionServiceTests.swift` contains sample `/Users/example/...` paths used as test fixtures. These are non-sensitive examples.
- Untracked IDE files were present locally: `.idea/` and `mytools.iml`. They did not contain confirmed secrets in this scan, but they can contain local workspace state and should remain ignored.

## Mitigations Added

- Updated `.gitignore` to ignore editor state, SwiftPM/Xcode-derived state, local env/secret files, generated app bundles, SQLite databases, and clipboard cache directories.
- Added `AGENTS.md` privacy guidance requiring future agents to avoid plaintext credentials, runtime clipboard data, and hard-coded user paths.

## Suggested Follow-Up

- Consider replacing historical absolute paths in `docs/superpowers/plans/2026-06-03-mac-tools-implementation.md` with repo-relative paths if that plan is still meant to be shared.
- When live translation is implemented, use Keychain for provider credentials and add tests that assert settings serialization never contains the credential fields.
