# Clipboard Cyclic Navigation And Brand Icon Design

## Goal

- Make the clipboard category tabs cycle with the horizontal arrow keys: Left from `全部` selects `收藏`, and Right from `收藏` selects `全部`.
- Preserve adjacent navigation through `全部`, `文本`, `图像`, and `收藏` for every other transition.
- Remove the sidebar subtitle `高效 · 便捷 · 智能`.
- Replace the remaining sidebar tools symbol with the current blue-purple MacTools brand icon already used by the menu bar and packaged application.

## Approaches Considered

1. Inject the existing runtime menu-bar image into `MainWorkspaceView` (recommended). This keeps one source asset and preserves the boundary between AppKit resource loading and reusable Core UI.
2. Add a second copy of the image to `MacToolsCore`. This would make previews convenient, but duplicates the asset and requires additional packaged resource-bundle handling.
3. Read `NSApplication.shared.applicationIconImage` from `MacToolsCore`. This avoids another file but couples reusable UI to global application state and is unreliable under `swift run` and previews.

## Design

`ClipboardPanelModeNavigator` remains the single testable navigation policy. Its previous/next calculation will wrap around `ClipboardPanelMode.allCases` instead of clamping at the first and last modes. `MainPanelView` continues to consume Left and Right key events through the existing monitor, so search focus, vertical list selection, and Return-key behavior remain unchanged.

`RuntimeMainWorkspaceView` will load the existing `MenuBarIcon.png` through the App target's current icon loader and pass it into `MainWorkspaceView`. The sidebar will render that image at the existing brand-badge footprint and remove the subtitle row. `MainWorkspaceView` requires callers to inject the brand image; isolated Core previews must explicitly provide their own preview image, so no legacy tools-symbol fallback remains.

A repository-wide symbol and text scan will confirm that no visible old tools logo or removed slogan remains. Module-specific SF Symbols are not brand logos and will remain unchanged.

## Verification

- Update focused navigation tests to assert all adjacent transitions and both wrap-around transitions.
- Add source-level UI wiring assertions for removal of the slogan and injection of the current icon resource.
- Run the focused tests, then `swift test`.
- Run `scripts/rebuild_and_run_app.sh` and inspect the clipboard sidebar in light and dark appearances, including keyboard focus, category wrapping, sidebar toggling, and absence of window chrome artifacts.
