# Manual Verification

- Launch with `swift run MacTools`.
- Confirm menu bar item appears as `MT`.
- Confirm Dock icon does not appear.
- Use `Option + Space` to open the main panel.
- Use `Option + 1` to open clipboard history.
- Copy text and confirm it appears in clipboard search.
- Copy a file and confirm filename/path appears.
- Copy a folder and confirm folder actions show Copy Path and Open in Terminal.
- Copy image data and confirm it is stored in the app cache.
- Select a clipboard item and press Enter; confirm it copies and attempts paste.
- Use Cmd+Enter; confirm it copies without sending paste.
- Short right-click in Finder; confirm the system menu appears.
- Long right-click a selected folder; confirm the context action window appears.
- Long right-click selected text before Baidu credentials are configured; confirm the translation service reports unconfigured state.
- Open settings and confirm permission status is visible.
- Build app bundle with `scripts/package_app.sh`.
- Launch `build/MacTools.app`.
