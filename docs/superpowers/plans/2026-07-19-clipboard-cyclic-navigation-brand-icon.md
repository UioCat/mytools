# Clipboard Cyclic Navigation And Brand Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add cyclic Left/Right clipboard category navigation and make the sidebar use the current MacTools icon without its old slogan.

**Architecture:** Keep category navigation in the existing pure `ClipboardPanelModeNavigator`. Keep brand asset loading in the executable target and explicitly inject a SwiftUI `Image` into the reusable `MainWorkspaceView`, reusing the same `MenuBarIcon.png` loader as the menu bar.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, Swift Package Manager, XCTest, macOS 26+

## Global Constraints

- Left from `全部` selects `收藏`, and Right from `收藏` selects `全部`.
- All other Left/Right transitions remain adjacent across `全部`, `文本`, `图像`, and `收藏`.
- Remove `高效 · 便捷 · 智能` and every remaining use of the legacy `wrench.and.screwdriver.fill` brand logo.
- Reuse `Sources/MacTools/Resources/MenuBarIcon.png`; do not add a duplicate brand asset or read global application icon state from `MacToolsCore`.
- Module-specific SF Symbols are not brand logos and remain unchanged.
- Preserve the existing search, vertical selection, Return, Command+Return, sidebar toggle, and Liquid Glass behavior.

---

### Task 1: Cyclic Clipboard Category Navigation

**Files:**
- Modify: `Tests/MacToolsCoreTests/ClipboardListViewTests.swift`
- Modify: `Sources/MacToolsCore/UI/MainPanelView.swift`

**Interfaces:**
- Consumes: `ClipboardPanelMode.allCases` in its existing order.
- Produces: `ClipboardPanelModeNavigator.mode(adjacentTo:direction:) -> ClipboardPanelMode` with cyclic boundary behavior.

- [ ] **Step 1: Write the failing boundary test**

Replace the clamping test with:

```swift
func testClipboardCategoryArrowNavigationWrapsAtFirstAndLastModes() {
    XCTAssertEqual(
        ClipboardPanelModeNavigator.mode(adjacentTo: .all, direction: .previous),
        .favorites
    )
    XCTAssertEqual(
        ClipboardPanelModeNavigator.mode(adjacentTo: .favorites, direction: .next),
        .all
    )
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --filter ClipboardListViewTests/testClipboardCategoryArrowNavigationWrapsAtFirstAndLastModes`

Expected: two assertion failures because the current implementation returns `.all` and `.favorites`.

- [ ] **Step 3: Implement cyclic navigation**

Replace the clamped index calculation in `ClipboardPanelModeNavigator.mode` with:

```swift
let offset = direction == .previous ? modes.count - 1 : 1
let nextIndex = (currentIndex + offset) % modes.count
return modes[nextIndex]
```

- [ ] **Step 4: Run focused navigation tests**

Run: `swift test --filter ClipboardListViewTests`

Expected: all `ClipboardListViewTests` pass.

- [ ] **Step 5: Commit the navigation change**

```sh
git add Tests/MacToolsCoreTests/ClipboardListViewTests.swift Sources/MacToolsCore/UI/MainPanelView.swift
git commit -m "Add cyclic clipboard category navigation"
```

---

### Task 2: Current Sidebar Brand Icon And Copy Cleanup

**Files:**
- Modify: `Tests/MacToolsCoreTests/MenuBarIconAssetTests.swift`
- Modify: `Sources/MacToolsCore/UI/MainWorkspaceView.swift`
- Modify: `Sources/MacTools/App/RuntimeViews.swift`
- Modify: `docs/manual-verification.md`

**Interfaces:**
- Consumes: `MenuBarLogoImage.make() -> NSImage` from the App target.
- Produces: `MainWorkspaceView.init(selectedModule:brandIcon:settings:clipboard:translation:)` where `brandIcon` is an explicitly injected SwiftUI `Image`.

- [ ] **Step 1: Write the failing brand-wiring test**

Add this test to `MenuBarIconAssetTests`:

```swift
func testSidebarUsesCurrentMenuBarAssetWithoutLegacyBranding() throws {
    let workspaceSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/MacToolsCore/UI/MainWorkspaceView.swift"
        ),
        encoding: .utf8
    )
    let runtimeSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/MacTools/App/RuntimeViews.swift"
        ),
        encoding: .utf8
    )

    XCTAssertTrue(workspaceSource.contains("private let brandIcon: Image"))
    XCTAssertTrue(runtimeSource.contains("brandIcon: Image(nsImage: MenuBarLogoImage.make())"))
    XCTAssertFalse(workspaceSource.contains("wrench.and.screwdriver.fill"))
    XCTAssertFalse(workspaceSource.contains("高效 · 便捷 · 智能"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `swift test --filter MenuBarIconAssetTests/testSidebarUsesCurrentMenuBarAssetWithoutLegacyBranding`

Expected: failures for missing image injection and remaining legacy strings.

- [ ] **Step 3: Inject and display the current icon**

Add `private let brandIcon: Image` to `MainWorkspaceView`, add a required `brandIcon: Image` initializer parameter, assign it, and replace the nested sidebar heading with:

```swift
HStack(spacing: 10) {
    brandIcon
        .resizable()
        .scaledToFit()
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)

    Text("MacTools")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MacToolsGlassTheme.textPrimary)
}
.padding(.horizontal, 6)
.padding(.bottom, 14)
```

Update the runtime call to begin with:

```swift
MainWorkspaceView(
    selectedModule: $router.selectedModule,
    brandIcon: Image(nsImage: MenuBarLogoImage.make())
) {
```

- [ ] **Step 4: Update the manual verification checklist**

After opening clipboard history, require the sidebar to show the current blue-purple ribbon icon without the slogan, and change the category keyboard check to verify both wrap-around transitions as well as adjacent transitions.

- [ ] **Step 5: Run focused asset and UI wiring tests**

Run: `swift test --filter MenuBarIconAssetTests`

Expected: all `MenuBarIconAssetTests` pass.

- [ ] **Step 6: Scan for legacy branding**

Run:

```sh
rg -n '高效 · 便捷 · 智能|wrench\.and\.screwdriver\.fill' Sources Tests
```

Expected: no matches.

- [ ] **Step 7: Commit the brand update**

```sh
git add Tests/MacToolsCoreTests/MenuBarIconAssetTests.swift Sources/MacToolsCore/UI/MainWorkspaceView.swift Sources/MacTools/App/RuntimeViews.swift docs/manual-verification.md
git commit -m "Use current icon in main sidebar"
```

---

### Task 3: Full Verification And Packaged UI Check

**Files:**
- Verify only: all files changed by Tasks 1 and 2.

**Interfaces:**
- Consumes: completed cyclic navigation and brand icon wiring.
- Produces: fresh automated and packaged-runtime evidence.

- [ ] **Step 1: Run the full unit suite**

Run: `swift test`

Expected: exit code 0 with zero failures.

- [ ] **Step 2: Check patch formatting and scope**

Run: `git diff --check HEAD~2..HEAD && git status --short`

Expected: no whitespace errors; only intentional progress/plan scratch files may be untracked.

- [ ] **Step 3: Rebuild and launch the packaged app**

Run: `scripts/rebuild_and_run_app.sh`

Expected: release build, app replacement, signing, and launch all complete successfully.

- [ ] **Step 4: Inspect the packaged clipboard UI**

Open clipboard history with `Option + 1`, show the sidebar, and verify the current blue-purple icon, absent slogan, Left wrap from `全部` to `收藏`, Right wrap back to `全部`, adjacent category navigation, contrasting light/dark backgrounds, focus, outside-click dismissal, resizing, and no gray outline, titlebar residue, rectangular shadow, or backing-layer artifact.
