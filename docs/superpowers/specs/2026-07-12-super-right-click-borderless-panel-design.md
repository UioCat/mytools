# Super Right-Click Borderless Panel Design

## Goal

Remove the unintended gray outline and rectangular system shadow around the super-right-click panel, and establish a permanent UI verification rule that prevents the artifact from returning.

## Root Cause

The SwiftUI panel content already draws its own rounded Liquid Glass surface. The AppKit shell still uses `.titled` and `.fullSizeContentView`, and enables `NSWindow.hasShadow`. AppKit window chrome and the system shadow follow the window frame rather than the rounded SwiftUI glass shape, which creates the gray edge visible above, below, and around the panel.

The main MacTools panel already avoids this problem with a borderless AppKit window, disabled system shadow, and rounded backing-layer clipping. The super-right-click panel did not use the same shell policy.

## Approaches Considered

1. **Fix the AppKit window shell — selected.** Use a borderless non-activating panel, disable the system window shadow, and clip both the hosting view and its AppKit frame view to the same 22 pt continuous corner radius as the SwiftUI surface.
2. **Cover the edge in SwiftUI.** A background-colored overlay could hide the artifact on one background but would fail over different windows and would not remove the underlying system chrome.
3. **Disable only the shadow.** This removes part of the artifact but leaves titled/full-size window chrome and does not guarantee clean rounded edges.

## Architecture

Add `ContextPanelWindowAppearance` to `MacToolsCore`. It exposes the context panel style mask, the system-shadow policy, the corner radius, and a reusable rounded-backing-layer configurator. `ContextPanelController` consumes this policy when creating its `NSPanel` and when installing each new `NSHostingView`.

No changes are made to super-right-click content, actions, translation, window layout, sizing, or positioning logic.

## Window Policy

- Style mask: `.borderless` plus `.nonactivatingPanel`.
- System shadow: disabled.
- Window/background opacity: transparent, unchanged.
- Floating and transient collection behavior: unchanged.
- Rounded clipping: 22 pt continuous corner radius on the hosting view and its AppKit frame view.
- SwiftUI Liquid Glass remains the only visible panel surface.

## Testing

- Add a regression test proving the context-panel mask contains neither `.titled` nor `.fullSizeContentView` and still contains `.nonactivatingPanel`.
- Prove system shadow is disabled.
- Instantiate a real `NSPanel` with the policy and verify it has no titlebar buttons.
- Verify rounded backing-layer clipping, transparent background, continuous corners, and the 22 pt radius.
- Run focused tests, the complete Swift test suite, and `scripts/rebuild_and_run_app.sh`.
- Visually verify the panel over contrasting light and dark backgrounds with no gray outline or rectangular system shadow outside the intended rounded glass surface.

## Permanent UI Rule

After every MacTools UI modification, inspect every affected floating panel and glass control for unintended gray outlines, titlebar residue, rectangular system shadows, or backing layers outside the intended rounded shape. Any such artifact must be removed before the change is considered complete. UI work must finish with a local rebuild and runtime visual check.
