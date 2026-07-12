# Super Right-Click Borderless Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove unintended gray window chrome and rectangular shadow from the super-right-click panel and make gray-edge inspection mandatory for future UI changes.

**Architecture:** Add a testable `ContextPanelWindowAppearance` policy to `MacToolsCore`. Apply the policy in `ContextPanelController`, then record the permanent runtime-verification rule in project guidance and Codex memory.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Package Manager, XCTest

## Global Constraints

- Keep the existing half-size panel dimensions and content behavior unchanged.
- Use `.borderless` plus `.nonactivatingPanel` and disable the AppKit system shadow.
- Clip the hosting view and its frame view to a 22 pt continuous rounded corner.
- Run `scripts/rebuild_and_run_app.sh` after the UI change.
- Future UI work must check for unintended gray outlines, titlebar residue, and rectangular system shadows.

---

### Task 1: Context panel window appearance regression

**Files:**
- Create: `Sources/MacToolsCore/Panels/ContextPanelWindowAppearance.swift`
- Create: `Tests/MacToolsCoreTests/ContextPanelWindowAppearanceTests.swift`
- Modify: `Sources/MacTools/App/ContextPanelController.swift`

**Interfaces:**
- Produces: `ContextPanelWindowAppearance.windowStyleMask`, `usesSystemWindowShadow`, `windowCornerRadius`, and `configureRoundedBackingLayer(_:)`.
- Consumes: AppKit `NSPanel`, `NSView`, and the existing 22 pt SwiftUI panel corner radius.

- [ ] **Step 1: Write the failing regression tests**

```swift
import AppKit
import XCTest
@testable import MacToolsCore

final class ContextPanelWindowAppearanceTests: XCTestCase {
    func testContextPanelHasNoTitledChromeOrRectangularSystemShadow() {
        let styleMask = ContextPanelWindowAppearance.windowStyleMask

        XCTAssertFalse(styleMask.contains(.titled))
        XCTAssertFalse(styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(ContextPanelWindowAppearance.usesSystemWindowShadow)
        XCTAssertEqual(ContextPanelWindowAppearance.windowCornerRadius, 22)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 210),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        XCTAssertNil(panel.standardWindowButton(.closeButton))
    }

    func testContextPanelBackingLayerClipsOutsideTheRoundedGlassShape() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 210))

        ContextPanelWindowAppearance.configureRoundedBackingLayer(view)

        let layer = try XCTUnwrap(view.layer)
        XCTAssertEqual(layer.cornerRadius, 22)
        XCTAssertEqual(layer.cornerCurve, .continuous)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertEqual(layer.backgroundColor, NSColor.clear.cgColor)
    }
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter ContextPanelWindowAppearanceTests`

Expected: FAIL because `ContextPanelWindowAppearance` does not exist.

- [ ] **Step 3: Implement the window policy**

```swift
import AppKit

public enum ContextPanelWindowAppearance {
    public static let windowStyleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    public static let usesSystemWindowShadow = false
    public static let windowCornerRadius: CGFloat = 22

    public static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
```

In `ContextPanelController.makePanel`, use `ContextPanelWindowAppearance.windowStyleMask`, remove titlebar-specific configuration, and set `panel.hasShadow = ContextPanelWindowAppearance.usesSystemWindowShadow`.

After assigning `panel.contentView = hostingView`, call the configurator on `hostingView` and its `superview` when present.

- [ ] **Step 4: Run GREEN**

Run: `swift test --filter ContextPanelWindowAppearanceTests`

Expected: 2 tests pass with zero failures.

- [ ] **Step 5: Commit the regression fix**

```bash
git add Sources/MacToolsCore/Panels/ContextPanelWindowAppearance.swift Sources/MacTools/App/ContextPanelController.swift Tests/MacToolsCoreTests/ContextPanelWindowAppearanceTests.swift
git commit -m "fix: remove super panel window chrome"
```

### Task 2: Permanent UI gray-edge rule

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/manual-verification.md`
- Create: `/Users/hanxun/.codex/memories/extensions/ad_hoc/notes/<timestamp>-mactools-ui-gray-border-check.md`

**Interfaces:**
- Produces: a project rule and long-term user preference requiring gray-edge inspection after every UI change.

- [ ] **Step 1: Add the project rule**

Add to `AGENTS.md`:

```markdown
## UI Visual Verification

- After every UI change, rebuild and inspect affected panels over contrasting light and dark backgrounds.
- Treat any unintended gray outline, titlebar residue, rectangular system shadow, or backing layer outside the intended rounded Liquid Glass shape as a release blocker; remove it before completion.
- For `NSPanel` surfaces, verify the AppKit style mask, `hasShadow`, and rounded backing-layer clipping instead of trying to cover window chrome inside SwiftUI.
```

Add a matching gray-edge check to `docs/manual-verification.md`.

- [ ] **Step 2: Add the explicitly requested memory note**

Create one ad-hoc note stating that every future MacTools UI modification must check for and remove unintended gray borders or rectangular shadows, then run the local rebuild script.

- [ ] **Step 3: Commit project documentation**

```bash
git add AGENTS.md docs/manual-verification.md
git commit -m "docs: require gray-edge UI verification"
```

### Task 3: Verification and local launch

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: completed borderless window policy and documentation.
- Produces: automated test, build, process, and manual-verification evidence.

- [ ] **Step 1: Run focused and full tests**

```bash
swift test --filter 'ContextPanelWindowAppearanceTests|SuperPanel(Layout|Content|Snapshot)Tests'
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Check patch hygiene**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and no uncommitted project files.

- [ ] **Step 3: Rebuild and launch**

Run: `scripts/rebuild_and_run_app.sh`

Expected: release build and signing succeed, the previous MacTools process stops, and the newest app launches.

- [ ] **Step 4: Runtime check**

Trigger super right click over a contrasting background and confirm there is no gray outline or rectangular shadow outside the 22 pt rounded glass surface. If the gesture cannot be automated safely, report the successful build/launch and leave this one visual check for the user.
