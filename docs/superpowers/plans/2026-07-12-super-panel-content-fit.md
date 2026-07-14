# Super Panel Content Fit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify selected files and folders around one copy-path action, preserve Finder-current-directory actions, and size the super-right-click panel so the standard eight layout buttons are visible without scrolling.

**Architecture:** Add an explicit file-system presentation context to `SuperPanelContent` so a selected folder is not confused with Finder's current directory. Keep the existing SwiftUI hierarchy and two-column grid, but let file-system and layout-only panels use a 320-point width and unscaled content-derived height capped at 620 points; text panels remain compact.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSPanel`, Swift Package Manager, XCTest.

## Global Constraints

- Selected files, selected folders, and selected image files show `复制文件路径` followed by configured window-layout buttons.
- Finder current-directory presentation keeps `新建文件`, `复制当前路径`, `在终端打开`, followed by configured window-layout buttons.
- Standard eight-button layout lists must be fully visible without scrolling.
- File-system and layout-only panels use a 320-point width and content-derived height capped at 620 points.
- Text and text-transit panels keep their existing 250-point compact width and height behavior.
- Preserve the existing Liquid Glass view hierarchy, two-column layout grid, borderless/nonactivating panel style, disabled system shadow, transparent backing layers, and 22-point continuous corner clipping.
- After UI changes, run `scripts/rebuild_and_run_app.sh` and visually reject any gray rectangular outline, titlebar residue, system shadow, or backing layer outside the rounded surface.

---

### Task 1: Separate Selected Items From Finder Current Directory

**Files:**
- Modify: `Tests/MacToolsCoreTests/SuperPanelContentTests.swift`
- Modify: `Sources/MacToolsCore/UI/SuperPanelContent.swift`
- Modify: `Sources/MacTools/App/ContextPanelController.swift`
- Modify: `Sources/MacTools/App/AppEnvironment.swift`
- Modify: `docs/manual-verification.md`

**Interfaces:**
- Produces: `SuperPanelFileSystemPresentation` with `.selectedItem` and `.finderCurrentDirectory` cases.
- Produces: `SuperPanelContent.fileSystem(item:windowLayoutButtons:presentation:)`, defaulting `presentation` to `.selectedItem`.
- Produces: `ContextPanelController.show(item:presentation:)`, defaulting `presentation` to `.selectedItem`.

- [ ] **Step 1: Complete the failing content tests**

Keep the existing uncommitted selected-folder and Finder-current-directory test cases. The selected folder must assert `content.actions.map(\.title) == ["复制文件路径", "左半屏"]`. The Finder-current-directory test must pass `presentation: .finderCurrentDirectory` and expect the three directory actions followed by the configured layout action.

- [ ] **Step 2: Run the focused tests and verify RED**

Run `swift test --filter SuperPanelContentTests`.

Expected: compilation fails because `presentation` and `.finderCurrentDirectory` do not exist yet, or the selected-folder assertion fails because folders still receive directory actions.

- [ ] **Step 3: Add the presentation context and minimal content logic**

Add in `SuperPanelContent.swift`:

```swift
public enum SuperPanelFileSystemPresentation: Equatable {
    case selectedItem
    case finderCurrentDirectory
}
```

Change the factory signature to:

```swift
public static func fileSystem(
    item: ClipboardItem,
    windowLayoutButtons: [WindowLayoutButton] = [],
    presentation: SuperPanelFileSystemPresentation = .selectedItem
) -> SuperPanelContent
```

Build actions from the presentation context:

```swift
switch presentation {
case .selectedItem:
    actions = [
        .init(id: .copyPath, title: "复制文件路径", systemImage: "doc.on.doc")
    ]
case .finderCurrentDirectory:
    actions = [
        .init(id: .createNewFile, title: "新建文件", systemImage: "plus.square.fill"),
        .init(id: .copyPath, title: "复制当前路径", systemImage: "folder.fill"),
        .init(id: .openTerminal, title: "在终端打开", systemImage: "terminal.fill")
    ]
}
```

Append layout descriptors exactly as today so configured order remains unchanged.

- [ ] **Step 4: Route Finder's synthetic folder through the directory presentation**

Change `ContextPanelController.show` to accept and forward the defaulted presentation:

```swift
func show(
    item: ClipboardItem,
    presentation: SuperPanelFileSystemPresentation = .selectedItem
) {
    let layoutButtons = windowLayoutButtons()
    let content = SuperPanelContent.fileSystem(
        item: item,
        windowLayoutButtons: layoutButtons,
        presentation: presentation
    )
    // Preserve the existing action handler.
}
```

In `AppEnvironment.showFinderCurrentFolder`, call:

```swift
contextPanel.show(item: item, presentation: .finderCurrentDirectory)
```

The `.fileSystem` route for an actually selected file or folder continues calling `contextPanel.show(item:)`, so it uses `.selectedItem`.

- [ ] **Step 5: Update manual verification wording**

In `docs/manual-verification.md`, state that selected folders, files, and image files show only `复制文件路径` plus layouts. Keep Finder blank current-directory behavior as three directory actions plus layouts. Remove the old 260-point/scroll expectation; Task 2 replaces it.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run `swift test --filter SuperPanelContentTests`.

Expected: all `SuperPanelContentTests` pass with zero failures.

- [ ] **Step 7: Commit Task 1**

```bash
git add Tests/MacToolsCoreTests/SuperPanelContentTests.swift Sources/MacToolsCore/UI/SuperPanelContent.swift Sources/MacTools/App/ContextPanelController.swift Sources/MacTools/App/AppEnvironment.swift docs/manual-verification.md
git commit -m "feat: unify selected file and folder actions"
```

---

### Task 2: Expand Panels To Fit Standard Layout Lists

**Files:**
- Modify: `Tests/MacToolsCoreTests/SuperPanelLayoutTests.swift`
- Modify: `Sources/MacToolsCore/UI/SuperPanelLayout.swift`
- Modify: `docs/manual-verification.md`

**Interfaces:**
- Consumes: `SuperPanelFileSystemPresentation.finderCurrentDirectory` from Task 1.
- Produces: `SuperPanelLayout.panelSize(for:)` returning 320-point width for `.fileSystem` and `.windowLayout` content, with content-derived height in the 130...620 point range.

- [ ] **Step 1: Write exact failing layout tests**

Create a reusable eight-button fixture and assert:

```swift
XCTAssertEqual(
    SuperPanelLayout.panelSize(
        for: .windowLayoutOnly(windowLayoutButtons: eightLayoutButtons)
    ),
    CGSize(width: 320, height: 332)
)
XCTAssertEqual(
    SuperPanelLayout.panelSize(for: selectedItemContent),
    CGSize(width: 320, height: 436)
)
XCTAssertEqual(
    SuperPanelLayout.panelSize(for: finderDirectoryContent),
    CGSize(width: 320, height: 552)
)
```

Retain the text-panel expectation `CGSize(width: 250, height: 161)`. Replace the old half-height cap test with a twenty-layout-button file-system fixture expecting height `620`.

- [ ] **Step 2: Run the focused layout tests and verify RED**

Run `swift test --filter SuperPanelLayoutTests`.

Expected: size assertions fail because file-system/layout-only content still uses 260-point width and half-height scaling.

- [ ] **Step 3: Implement expanded content-derived sizing**

Keep the existing legacy content-height estimate, then branch by kind:

```swift
let isExpandedPanel = content.kind == .fileSystem || content.kind == .windowLayout

if isExpandedPanel {
    return CGSize(
        width: 320,
        height: min(max(legacyHeight, 130), 620)
    )
}

return CGSize(
    width: 500 * scale,
    height: min(max(legacyHeight, 260), 620) * scale
)
```

Do not change header metrics, action-row metrics, grid columns, button styling, or `ContextActionView`'s existing `ScrollView`. The larger standard height prevents scrolling for eight layouts, while the 620-point cap retains safe overflow behavior for unusually large custom configurations.

- [ ] **Step 4: Update manual size verification**

Document that file-system and layout-only panels use a 320-point width, standard eight-layout content is fully visible without a scrollbar, and oversized custom configurations may still scroll at the safety cap.

- [ ] **Step 5: Run focused and combined tests and verify GREEN**

Run:

```bash
swift test --filter SuperPanelLayoutTests
swift test --filter 'SuperPanel(Content|Layout|Snapshot)Tests'
```

Expected: all selected tests pass with zero failures.

- [ ] **Step 6: Commit Task 2**

```bash
git add Tests/MacToolsCoreTests/SuperPanelLayoutTests.swift Sources/MacToolsCore/UI/SuperPanelLayout.swift docs/manual-verification.md
git commit -m "feat: expand super panel to fit layout actions"
```

---

### Task 3: Full Verification And Live UI Inspection

**Files:**
- Verify only: `Sources/MacToolsCore/Panels/ContextPanelWindowAppearance.swift`
- Verify only: `Sources/MacTools/App/ContextPanelController.swift`
- Verify only: `docs/manual-verification.md`

**Interfaces:**
- Consumes: completed content routing and sizing from Tasks 1 and 2.
- Produces: fresh automated and live-app verification evidence.

- [ ] **Step 1: Run full automated verification**

```bash
swift test
git diff --check
```

Expected: all tests pass with zero failures and diff check exits successfully.

- [ ] **Step 2: Rebuild and launch the local app**

Run `scripts/rebuild_and_run_app.sh`.

Expected: release build, signing, replacement, and relaunch all succeed.

- [ ] **Step 3: Verify the launched process**

```bash
pgrep -x MacTools
ps -p "$(pgrep -x MacTools | head -n 1)" -o pid=,command=
```

Expected: the executable path is `./build/MacTools.app/Contents/MacOS/MacTools`.

- [ ] **Step 4: Inspect real super-right-click panels**

Trigger and capture these cases:

1. Non-Finder empty selection: all eight layouts visible, no scrollbar.
2. Finder selected file or folder: `复制文件路径` plus all eight layouts visible.
3. Finder blank current directory: three directory actions plus all eight layouts visible.

Inspect the rounded edge over contrasting light and dark backgrounds. Reject gray rectangular outlines, titlebar residue, system shadow, backing layers outside the 22-point rounded surface, clipping, or unwanted standard-content scrollbars.

- [ ] **Step 5: Confirm final repository state**

Run `git status --short` and `git log -5 --oneline`.

Expected: no uncommitted source/test/doc changes remain and both implementation commits are present.
