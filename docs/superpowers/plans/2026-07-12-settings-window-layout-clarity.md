# Settings Window Layout Clarity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make window-layout previews obvious at a glance and let Settings fill the available desktop width without losing its compact fallback.

**Architecture:** A small UI presentation-policy file supplies the responsive two-column decision and inset preview geometry. `SettingsView` uses that policy to stretch existing sections and draw each mode from its existing `WindowLayoutMode.previewSegment`; persistence, shortcut validation, and actions stay unchanged.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, XCTest.

## Global Constraints

- Keep the existing Settings header, glass theme, 8-point rhythm, action order, persistence callbacks, shortcut validation, and accessibility labels.
- At 694 points or more of inner content width, show two flexible top columns and a full-width Window Layout editor.
- Below 694 points, stack all Settings sections without horizontal clipping.
- Every preview uses a neutral screen frame plus an inset system-blue target region derived from `WindowLayoutMode.previewSegment`.
- Do not alter the `WindowLayoutSettings` data schema or add dependencies.
- Preserve the borderless Liquid Glass window; final visual QA must reject gray rectangular outlines, titlebar residue, system shadows, and backing layers outside rounded corners.

---

### Task 1: Add Testable Presentation Policy

**Files:**

- Create: `Sources/MacToolsCore/UI/WindowLayoutSettingsPresentation.swift`
- Create: `Tests/MacToolsCoreTests/WindowLayoutSettingsPresentationTests.swift`

**Interfaces:**

- Produces `SettingsPageColumnArrangement` (`.twoColumns`, `.stacked`).
- Produces `SettingsPageLayout.columnArrangement(for:)`.
- Produces `WindowLayoutPreviewGeometry.screenFrame(in:)` and `targetFrame(for:in:)`.

- [ ] **Step 1: Write the failing presentation tests**

Create `Tests/MacToolsCoreTests/WindowLayoutSettingsPresentationTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import MacToolsCore

final class WindowLayoutSettingsPresentationTests: XCTestCase {
    func testSettingsPageSelectsTwoColumnsOnlyWhenBothColumnsFit() {
        XCTAssertEqual(SettingsPageLayout.primaryColumnMinimumWidth, 320)
        XCTAssertEqual(SettingsPageLayout.secondaryColumnMinimumWidth, 360)
        XCTAssertEqual(SettingsPageLayout.columnSpacing, 14)
        XCTAssertEqual(SettingsPageLayout.minimumTwoColumnContentWidth, 694)
        XCTAssertEqual(SettingsPageLayout.columnArrangement(for: 693), .stacked)
        XCTAssertEqual(SettingsPageLayout.columnArrangement(for: 694), .twoColumns)
    }

    func testPreviewGeometryFramesAndInsetsEveryTargetRegion() {
        let bounds = CGRect(x: 0, y: 0, width: 36, height: 24)
        XCTAssertEqual(WindowLayoutPreviewGeometry.screenFrame(in: bounds), CGRect(x: 1, y: 1, width: 34, height: 22))
        XCTAssertEqual(WindowLayoutPreviewGeometry.targetFrame(for: .leftHalf.previewSegment, in: bounds), CGRect(x: 3, y: 3, width: 15, height: 18))
        XCTAssertEqual(WindowLayoutPreviewGeometry.targetFrame(for: .rightThird.previewSegment, in: bounds), CGRect(x: 25, y: 3, width: 10, height: 18))
        XCTAssertEqual(WindowLayoutPreviewGeometry.targetFrame(for: .maximize.previewSegment, in: bounds), CGRect(x: 3, y: 3, width: 30, height: 18))
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run `swift test --filter WindowLayoutSettingsPresentationTests`.

Expected: compilation fails because `SettingsPageLayout` and `WindowLayoutPreviewGeometry` do not exist.

- [ ] **Step 3: Implement the minimum policy**

Create `Sources/MacToolsCore/UI/WindowLayoutSettingsPresentation.swift`:

```swift
import CoreGraphics

enum SettingsPageColumnArrangement: Equatable {
    case twoColumns
    case stacked
}

enum SettingsPageLayout {
    static let primaryColumnMinimumWidth: CGFloat = 320
    static let secondaryColumnMinimumWidth: CGFloat = 360
    static let columnSpacing: CGFloat = 14
    static let minimumTwoColumnContentWidth = primaryColumnMinimumWidth + secondaryColumnMinimumWidth + columnSpacing

    static func columnArrangement(for availableWidth: CGFloat) -> SettingsPageColumnArrangement {
        availableWidth >= minimumTwoColumnContentWidth ? .twoColumns : .stacked
    }
}

enum WindowLayoutPreviewGeometry {
    static func screenFrame(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 1, dy: 1)
    }

    static func targetFrame(for segment: WindowLayoutPreviewSegment, in bounds: CGRect) -> CGRect {
        let placementArea = screenFrame(in: bounds).insetBy(dx: 2, dy: 2)
        return CGRect(
            x: placementArea.minX + placementArea.width * segment.x,
            y: placementArea.minY + placementArea.height * segment.y,
            width: placementArea.width * segment.width,
            height: placementArea.height * segment.height
        )
    }
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run `swift test --filter WindowLayoutSettingsPresentationTests`.

Expected: 2 tests pass with zero failures.

- [ ] **Step 5: Commit the policy**

Run:

```sh
git add Sources/MacToolsCore/UI/WindowLayoutSettingsPresentation.swift Tests/MacToolsCoreTests/WindowLayoutSettingsPresentationTests.swift
git commit -m "feat: define settings layout presentation policy"
```

### Task 2: Stretch Settings and Clarify Layout Previews

**Files:**

- Modify: `Sources/MacToolsCore/UI/SettingsView.swift:80-118`
- Modify: `Sources/MacToolsCore/UI/SettingsView.swift:740-940`
- Modify: `Tests/MacToolsCoreTests/WindowLayoutSettingsPresentationTests.swift`

**Interfaces:**

- Consumes `SettingsPageLayout` and `WindowLayoutPreviewGeometry` from Task 1.
- Preserves `primarySettingsColumn`, `secondarySettingsColumn`, `windowLayoutSection`, `WindowLayoutMode.previewSegment`, and all action-cell callbacks.
- Produces a flexible two-column desktop Settings layout, a stacked narrow layout, and 36-by-24-point framed previews.

- [ ] **Step 1: Add the failing maximized-preview regression**

Append to `WindowLayoutSettingsPresentationTests`:

```swift
func testMaximizedPreviewLeavesVisibleSpaceInsideScreenFrame() {
    let bounds = CGRect(x: 0, y: 0, width: 36, height: 24)
    let screen = WindowLayoutPreviewGeometry.screenFrame(in: bounds)
    let target = WindowLayoutPreviewGeometry.targetFrame(for: .maximize.previewSegment, in: bounds)

    XCTAssertGreaterThan(target.minX, screen.minX)
    XCTAssertGreaterThan(target.minY, screen.minY)
    XCTAssertLessThan(target.maxX, screen.maxX)
    XCTAssertLessThan(target.maxY, screen.maxY)
}
```

- [ ] **Step 2: Run the new test and verify RED**

Run `swift test --filter WindowLayoutSettingsPresentationTests/testMaximizedPreviewLeavesVisibleSpaceInsideScreenFrame`.

Expected: compilation fails because the test is not yet in the target.

- [ ] **Step 3: Replace the fixed-width Settings composition**

In `SettingsView`, replace the 900-point page ceiling, 320/440-point fixed columns, 774-point Window Layout width, and 440-point narrow width. Wrap the existing scroll view in a `GeometryReader`, calculate `let innerWidth = max(0, geometry.size.width - 44)`, and select this composition:

```swift
@ViewBuilder
private func settingsColumns(availableWidth: CGFloat) -> some View {
    switch SettingsPageLayout.columnArrangement(for: availableWidth) {
    case .twoColumns:
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: SettingsPageLayout.columnSpacing) {
                primarySettingsColumn
                    .frame(minWidth: SettingsPageLayout.primaryColumnMinimumWidth, maxWidth: .infinity, alignment: .topLeading)
                secondarySettingsColumn
                    .frame(minWidth: SettingsPageLayout.secondaryColumnMinimumWidth, maxWidth: .infinity, alignment: .topLeading)
            }
            windowLayoutSection
        }
    case .stacked:
        VStack(alignment: .leading, spacing: 14) {
            primarySettingsColumn
            secondarySettingsColumn
            windowLayoutSection
        }
    }
}
```

The returned stack, both column views, and `windowLayoutSection` use `.frame(maxWidth: .infinity, alignment: .topLeading)`. Leave section contents and save behavior untouched.

- [ ] **Step 4: Draw the preview with the new geometry**

Change `WindowLayoutModePreviewIcon` to a 36-by-24-point frame. In `WindowLayoutPreviewIcon`, create `bounds`, `screen`, and a `target` per segment from `WindowLayoutPreviewGeometry`. Draw the screen with `Color.primary.opacity(0.12)` fill and `Color.primary.opacity(0.34)` 1-point border. Draw the target with `MacToolsGlassTheme.activeBlue.opacity(index == 0 ? 0.82 : 0.58)` plus a 0.8-point blue stroke at 0.88 opacity. Retain the existing aspect ratio, hover state, disabled opacity, switch, shortcut field, and remove button.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```sh
swift test --filter WindowLayoutSettingsPresentationTests
swift test --filter WindowLayoutCalculatorTests
```

Expected: all focused tests pass with zero failures.

- [ ] **Step 6: Commit the Settings UI**

Run:

```sh
git add Sources/MacToolsCore/UI/SettingsView.swift Tests/MacToolsCoreTests/WindowLayoutSettingsPresentationTests.swift
git commit -m "feat: clarify and expand settings layout editor"
```

### Task 3: Document and Verify the Live Settings Surface

**Files:**

- Modify: `docs/manual-verification.md`
- Verify: `Sources/MacToolsCore/UI/SettingsView.swift`
- Verify: `Sources/MacToolsCore/UI/WindowLayoutSettingsPresentation.swift`

**Interfaces:**

- Consumes the responsive Settings layout and framed preview treatment.
- Produces repeatable wide/narrow and light/dark visual QA instructions.

- [ ] **Step 1: Update the manual checklist**

Replace the generic Window Layout check with:

```markdown
- Open Settings on a wide window and confirm the two top setting columns stretch across the usable content width; the Window Layout section spans the full width below them with no large unused right-hand area.
- In Window Layout, confirm every preview has a visible neutral screen frame and blue inset target region. Verify left/right halves, one-third, two-thirds, centered, and maximized layouts are distinguishable before reading their labels; narrow the window and confirm sections stack without clipping controls.
```

- [ ] **Step 2: Run complete automated verification**

Run:

```sh
swift test
git diff --check
```

Expected: the full suite has zero failures and the diff check exits with status 0.

- [ ] **Step 3: Rebuild and inspect**

Run `scripts/rebuild_and_run_app.sh`, then open Settings on contrasting light and dark backgrounds. Inspect first at a wide width and then below the 694-point inner-width breakpoint. Reject faint previews, indistinguishable regions, clipping, unused wide-editor space, gray rectangular window outlines, titlebar residue, system shadows, or rectangular backing layers outside the glass shape.

- [ ] **Step 4: Commit verification documentation**

Run:

```sh
git add docs/manual-verification.md
git commit -m "docs: verify settings layout clarity"
```
