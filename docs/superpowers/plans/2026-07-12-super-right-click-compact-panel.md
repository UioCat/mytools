# Super Right-Click Compact Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Halve the super-right-click panel width and height, make its header compact, and remove window-layout actions from all text-selection flows.

**Architecture:** Add a shared `SuperPanelLayout` policy in `MacToolsCore` for panel sizing and header metrics. Use it from both the SwiftUI surface and the AppKit controller, and keep text-vs-file action selection in `SuperPanelContent`.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, XCTest

## Global Constraints

- Text panel width is exactly 250 pt; file/folder panel width is exactly 260 pt.
- Panel height is exactly 0.5 times the previous capped dynamic height, with a resulting 130–310 pt range.
- Text and text-transit content never expose window-layout actions.
- File and folder content keep configured window-layout actions.
- Overflowing body content must scroll rather than clip.
- Run `scripts/rebuild_and_run_app.sh` after code changes.

---

### Task 1: Shared panel layout policy

**Files:**
- Create: `Sources/MacToolsCore/UI/SuperPanelLayout.swift`
- Create: `Tests/MacToolsCoreTests/SuperPanelLayoutTests.swift`

**Interfaces:**
- Consumes: `SuperPanelContent`, `SuperPanelKind`, and `SuperPanelActionID.isWindowLayoutButton`.
- Produces: `SuperPanelLayout.panelSize(for:) -> CGSize` and public compact-header metric constants.

- [ ] **Step 1: Write failing layout tests**

```swift
import XCTest
@testable import MacToolsCore

final class SuperPanelLayoutTests: XCTestCase {
    func testTextPanelUsesHalfWidthAndHalfDynamicHeight() {
        let content = SuperPanelContent.text(
            originalText: "hello",
            translation: .success(.init(translatedText: "你好", providerID: "test"))
        )

        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).width, 250)
        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 161)
    }

    func testEmptyLayoutPanelUsesHalfMinimumHeight() {
        let content = SuperPanelContent.windowLayoutOnly(windowLayoutButtons: [])
        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 130)
    }

    func testLargeFolderPanelUsesHalfMaximumHeight() {
        let buttons = (0..<8).map {
            WindowLayoutButton(id: "layout.\($0)", title: "布局 \($0)", modes: [.maximize])
        }
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: "Project",
            searchableText: "/tmp/Project",
            text: nil,
            originalPath: "/tmp/Project",
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "访达",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        let content = SuperPanelContent.fileSystem(item: item, windowLayoutButtons: buttons)

        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).width, 260)
        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 310)
    }

    func testHeaderUsesCompactMetrics() {
        XCTAssertEqual(SuperPanelLayout.headerIconSize, 36)
        XCTAssertEqual(SuperPanelLayout.headerTitleFontSize, 16)
        XCTAssertEqual(SuperPanelLayout.headerSubtitleFontSize, 11)
        XCTAssertEqual(SuperPanelLayout.headerTrailingIconFontSize, 18)
        XCTAssertEqual(SuperPanelLayout.headerHorizontalPadding, 14)
        XCTAssertEqual(SuperPanelLayout.headerTopPadding, 12)
        XCTAssertEqual(SuperPanelLayout.headerBottomPadding, 10)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter SuperPanelLayoutTests`

Expected: FAIL because `SuperPanelLayout` does not exist.

- [ ] **Step 3: Implement the shared policy**

```swift
import Foundation

public enum SuperPanelLayout {
    public static let scale: CGFloat = 0.5
    public static let headerIconSize: CGFloat = 36
    public static let headerIconFontSize: CGFloat = 16
    public static let headerTitleFontSize: CGFloat = 16
    public static let headerSubtitleFontSize: CGFloat = 11
    public static let headerTrailingIconFontSize: CGFloat = 18
    public static let headerAccessorySize: CGFloat = 20
    public static let headerSpacing: CGFloat = 10
    public static let headerTextSpacing: CGFloat = 2
    public static let headerHorizontalPadding: CGFloat = 14
    public static let headerTopPadding: CGFloat = 12
    public static let headerBottomPadding: CGFloat = 10

    public static func panelSize(for content: SuperPanelContent) -> CGSize {
        let previewRowsHeight = CGFloat(content.previewRows.count) * 46
        let primaryActionCount = content.actions.filter { !$0.id.isWindowLayoutButton }.count
        let windowLayoutActionCount = content.actions.count - primaryActionCount
        let windowLayoutRows = CGFloat((windowLayoutActionCount + 1) / 2)
        let actionsHeight = CGFloat(primaryActionCount) * 58
            + (windowLayoutActionCount > 0 ? 42 + windowLayoutRows * 44 : 0)
        let legacyHeight = 92
            + previewRowsHeight
            + estimatedExpandedTextHeight(for: content)
            + actionsHeight
            + 22
        let cappedLegacyHeight = min(max(legacyHeight, 260), 620)
        let legacyWidth: CGFloat = content.kind == .fileSystem ? 520 : 500

        return CGSize(width: legacyWidth * scale, height: cappedLegacyHeight * scale)
    }

    private static func estimatedExpandedTextHeight(for content: SuperPanelContent) -> CGFloat {
        guard content.kind == .text || content.kind == .textTransit else { return 0 }
        let characterCount = content.previewRows.reduce(0) { $0 + $1.value.count }
        guard characterCount > 120 else { return 0 }
        return min(CGFloat(characterCount / 48) * 18, 280)
    }
}
```

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter SuperPanelLayoutTests`

Expected: PASS.

- [ ] **Step 5: Commit the layout policy**

```bash
git add Sources/MacToolsCore/UI/SuperPanelLayout.swift Tests/MacToolsCoreTests/SuperPanelLayoutTests.swift
git commit -m "feat: add compact super panel layout policy"
```

### Task 2: Remove layout actions from text flows

**Files:**
- Modify: `Sources/MacToolsCore/UI/SuperPanelContent.swift`
- Modify: `Sources/MacTools/App/ContextPanelController.swift`
- Modify: `Tests/MacToolsCoreTests/SuperPanelContentTests.swift`

**Interfaces:**
- Consumes: existing `SuperPanelContent.text`, `SuperPanelContent.textTransit`, and `ContextPanelController.showText` flows.
- Produces: text content whose `actions` never contains an ID where `isWindowLayoutButton == true`.

- [ ] **Step 1: Change content expectations to reject layout actions**

Update `testTextPanelStillOffersTransitWhenTranslationIsNotConfigured` so configured buttons are supplied but the expected IDs and titles are only:

```swift
XCTAssertEqual(content.actions.map(\.id), [.textTransit])
XCTAssertEqual(content.actions.map(\.title), ["文本悬浮中转"])
XCTAssertFalse(content.actions.contains { $0.id.isWindowLayoutButton })
```

Add:

```swift
func testTextTransitPanelIgnoresConfiguredWindowLayoutButtons() {
    let content = SuperPanelContent.textTransit(
        text: "hello",
        windowLayoutButtons: [
            WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf])
        ]
    )

    XCTAssertEqual(content.actions.map(\.id), [.copyTransitText])
    XCTAssertFalse(content.actions.contains { $0.id.isWindowLayoutButton })
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter SuperPanelContentTests`

Expected: FAIL because text and text-transit builders currently append layout descriptors.

- [ ] **Step 3: Stop generating and forwarding layout actions for text**

In `SuperPanelContent.text` and `SuperPanelContent.textTransit`, keep their existing parameters for source compatibility but stop appending `windowLayoutActionDescriptors`.

In `ContextPanelController`:

```swift
func showText(...) {
    let content = SuperPanelContent.text(
        originalText: originalText,
        translation: translation,
        isTranslationLoading: isTranslationLoading
    )
    // Keep translatedText extraction and presentation unchanged.
}

private func showTextTransit(_ text: String) {
    let content = SuperPanelContent.textTransit(text: text)
    // Reuse the existing performTextAction closure without layout buttons.
}
```

Remove `windowLayoutButtons` from `performTextAction` and route `.windowLayoutButton` through its existing unexpected-action logging branch. File action handling remains unchanged.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter SuperPanelContentTests`

Expected: PASS.

- [ ] **Step 5: Commit the content-policy change**

```bash
git add Sources/MacToolsCore/UI/SuperPanelContent.swift Sources/MacTools/App/ContextPanelController.swift Tests/MacToolsCoreTests/SuperPanelContentTests.swift
git commit -m "feat: remove layout actions from text super panels"
```

### Task 3: Apply compact sizing and scrolling UI

**Files:**
- Modify: `Sources/MacToolsCore/UI/ContextActionView.swift`
- Modify: `Sources/MacTools/App/ContextPanelController.swift`
- Modify: `Tests/MacToolsCoreTests/SuperPanelSnapshotTests.swift`

**Interfaces:**
- Consumes: `SuperPanelLayout.panelSize(for:)` and its header constants.
- Produces: a fixed half-size panel with a compact fixed header and scrollable body.

- [ ] **Step 1: Update the opt-in snapshot rendering contract**

Pass each fixture's `SuperPanelContent` into `writeSnapshot`. Derive the proposed size from `SuperPanelLayout.panelSize(for:)`, add the existing 40 pt preview padding on each edge, and keep both text and folder snapshot fixtures. This preserves an opt-in visual artifact for the dimensions already covered by the failing tests in Task 1.

- [ ] **Step 2: Run the snapshot test path before UI wiring**

Run: `MACTOOLS_SUPER_PANEL_SNAPSHOT_DIR=$(mktemp -d) swift test --filter SuperPanelSnapshotTests`

Expected: PASS and generate baseline PNGs. Inspect their dimensions and note that the production view still renders with its old hard-coded width before Step 4; the Task 1 sizing tests are the automated RED contract for this UI change.

- [ ] **Step 3: Use the shared size in AppKit**

Replace `ContextPanelController.panelSize(for:)` and `estimatedExpandedTextHeight(for:)` with:

```swift
private func panelSize(for content: SuperPanelContent) -> NSSize {
    SuperPanelLayout.panelSize(for: content)
}
```

Change `makePanel`'s initial content rect to 260 × 210 pt so its fallback size also reflects the halved 520 × 420 pt frame.

- [ ] **Step 4: Make the SwiftUI panel compact and scroll-safe**

In `ContextActionView`, compute `let size = SuperPanelLayout.panelSize(for: content)`. Keep the header and its divider outside a vertical `ScrollView`; move the preview, its divider, and action section into the scroll view. Apply:

```swift
.frame(width: size.width, height: size.height)
.glassEffect(.regular, in: panelShape)
```

Remove the old hard-coded `panelWidth` and vertical `fixedSize` behavior. Replace header dimensions with the `SuperPanelLayout` compact metrics and add `minimumScaleFactor(0.8)` to the one-line title and subtitle.

- [ ] **Step 5: Run focused UI tests and verify GREEN**

Run:

```bash
swift test --filter SuperPanelLayoutTests
MACTOOLS_SUPER_PANEL_SNAPSHOT_DIR=$(mktemp -d) swift test --filter SuperPanelSnapshotTests
```

Expected: PASS and two PNG snapshots are written.

- [ ] **Step 6: Commit the compact UI**

```bash
git add Sources/MacToolsCore/UI/ContextActionView.swift Sources/MacTools/App/ContextPanelController.swift Tests/MacToolsCoreTests/SuperPanelSnapshotTests.swift
git commit -m "feat: compact super right click panel UI"
```

### Task 4: Full verification and local launch

**Files:**
- Modify if required: `docs/manual-verification.md`

**Interfaces:**
- Consumes: the completed compact panel implementation.
- Produces: automated and local runtime verification evidence.

- [ ] **Step 1: Run the full suite**

Run: `swift test`

Expected: all tests pass with zero failures.

- [ ] **Step 2: Check patch hygiene and sensitive content**

Run:

```bash
git diff --check
rg -n --hidden --glob '!.git/**' --glob '!.worktrees/**' --glob '!.build/**' --glob '!build/**' -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
```

Expected: no whitespace errors and no newly introduced credentials.

- [ ] **Step 3: Rebuild and launch the latest app**

Run: `scripts/rebuild_and_run_app.sh`

Expected: the script builds the application bundle, stops the prior MacTools process, and launches the new build.

- [ ] **Step 4: Report manual checks**

Confirm selected text shows no layout section, folder/file content retains layout actions, the panel frame is half-sized, and the compact header matches the approved screenshot direction. If UI interaction cannot be automated, state that the app was launched and identify the checks left for the user.
