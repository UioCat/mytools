# Super Right-Click Compact Panel Design

## Goal

Reduce every super-right-click panel to one half of its current width and height, remove window-layout actions whenever the captured selection is text, and make the header summary area visibly more compact.

## Scope

- Text panel width changes from 500 pt to 250 pt.
- File and folder panel width changes from 520 pt to 260 pt.
- The existing content-based height calculation is preserved, then scaled by 0.5. The height range changes from 260–620 pt to 130–310 pt.
- Text and text-transit panels never include window-layout actions.
- File and folder panels keep their configured window-layout actions.
- The header icon, title, subtitle, trailing accessory, spacing, and padding all become smaller.
- Content that does not fit the halved height remains reachable through vertical scrolling instead of being clipped.

## Architecture

Add a shared `SuperPanelLayout` policy to `MacToolsCore`. It owns panel size calculation and compact header metrics. `ContextActionView` uses it to size the SwiftUI surface, while `ContextPanelController` uses the same policy to size the AppKit panel.

Keep content policy in `SuperPanelContent`: text and text-transit builders expose only text-related actions, while file-system builders continue to append configured window-layout actions. The controller stops requesting or forwarding layout buttons for text flows.

## UI Design

The header remains fixed at the top of the panel. Its visual hierarchy is preserved with smaller metrics:

- Header icon box: 36 × 36 pt.
- Header icon font: 16 pt.
- Title font: 16 pt.
- Subtitle font: 11 pt.
- Trailing icon: 18 pt.
- Header horizontal padding: 14 pt.
- Header top/bottom padding: 12/10 pt.
- Header internal spacing: 10 pt.

The preview and action sections share the remaining vertical space in a scrollable body. Existing action labels, behavior, hover states, and file/window-layout functionality remain unchanged.

## Content Rules

### Selected text

- Header and original/translated preview remain visible.
- Loading, success, missing-configuration, network-error, and provider-error translation states remain unchanged.
- Available actions are limited to `复制译文` when a translation succeeds and `文本悬浮中转`.
- No `窗口布局` heading or layout buttons are generated.

### Text transit

- Shows the transit text and `复制文本`.
- No window-layout actions are generated.

### Folder

- Keeps copy path, create file, open terminal, Claude Code actions, and configured window-layout actions.

### File and image file

- Keep copy path, reveal in Finder, Claude Code actions, and configured window-layout actions.

### Image data and unknown content

- Existing behavior remains unchanged: no context panel is shown.

## Error Handling

Existing action and translation error handling remains unchanged. The layout change adds no new runtime failure mode. Scrolling is the fallback when content exceeds the new panel height.

## Testing and Verification

- Add unit tests for exact half-width and half-height sizing, including min/max height caps.
- Update content tests to prove configured layout buttons are ignored for text and text-transit content.
- Keep file-system tests proving layout buttons remain present.
- Run focused tests, then the full `swift test` suite.
- Run `scripts/rebuild_and_run_app.sh` so the local app uses the latest build.
- Use the super-right-click manual checks for selected text, folder, and file scenarios.
