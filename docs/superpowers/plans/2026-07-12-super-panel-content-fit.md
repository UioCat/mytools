# Super Panel Content Fit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify selected file and folder actions as “复制文件路径” plus window layouts, while expanding the super-right-click panel so the standard eight layout buttons are fully visible without scrolling.

**Architecture:** Add an explicit file-system presentation context so a selected folder can share the selected-file action set without changing Finder-background directory actions. Replace the half-scaled legacy height estimate for file-system/layout panels with content-fit metrics, and only wrap the body in a `ScrollView` when the calculated required height exceeds the 620-point safety cap.

**Tech Stack:** Swift 6, SwiftUI, AppKit `NSPanel`, Swift Package Manager, XCTest.

## Global Constraints

- Selected files, folders, and image files show `复制文件路径` followed by all configured window-layout buttons.
- Finder background keeps `新建文件`, `复制当前路径`, `在终端打开`, followed by all configured window-layout buttons.
- File-system and window-layout panels use a 320-point width and show the standard eight layouts without scrolling.
- Text-selection panels retain their current compact 250-point width and behavior.
- `NSPanel` remains borderless/nonactivating, has no system shadow, and clips transparent backing layers to the 22-point continuous corner radius.
- Every production change follows red-green-refactor and the final UI change runs `scripts/rebuild_and_run_app.sh`.

---

### Task 1: Separate Selected Items From Finder Current Directory

**Files:**
- Modify: `Sources/MacToolsCore/UI/SuperPanelContent.swift`
- Modify: `Sources/MacTools/App/ContextPanelController.swift`
- Modify: `Sources/MacTools/App/AppEnvironment.swift`
- Test: `Tests/MacToolsCoreTests/SuperPanelContentTests.swift`

**Interfaces:**
- Produces: `SuperPanelFileSystemPresentation` with `.selectedItem` and `.finderCurrentDirectory` cases.
- Produces: `SuperPanelContent.fileSystem(item:windowLayoutButtons:presentation:)` with `.selectedItem` as its default presentation.
- Consumes: `AppEnvironment.showFinderCurrentFolder` passes `.finderCurrentDirectory`; ordinary captured file-system results use the default `.selectedItem`.

- [ ] **Step 1: Replace the folder-action expectation with selected-item and Finder-directory tests**

```swift
func testSelectedFolderPanelUsesTheSelectedFileActionSet() {
    let content = SuperPanelContent.fileSystem(
        item: .testItem(
            kind: .folder,
            displayTitle: "Project",
            originalPath: "/Users/example/Project",
            sourceApp: "访达"
        ),
        windowLayoutButtons: [
            WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf])
        ]
    )

    XCTAssertEqual(content.actions.map(\.id), [
        .copyPath,
        .windowLayoutButton("mode.leftHalf")
    ])
    XCTAssertEqual(content.actions.map(\.title), ["复制文件路径", "左半屏"])
}

func testFinderCurrentDirectoryKeepsDirectoryActions() {
    let content = SuperPanelContent.fileSystem(
        item: .testItem(
            kind: .folder,
            displayTitle: "Project",
            originalPath: "/Users/example/Project",
            sourceApp: "访达"
        ),
        windowLayoutButtons: [
            WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf])
        ],
        presentation: .finderCurrentDirectory
    )

    XCTAssertEqual(content.actions.map(\.title), [
        "新建文件", "复制当前路径", "在终端打开", "左半屏"
    ])
}
```

- [ ] **Step 2: Run the content tests and verify RED**

Run: `swift test --filter SuperPanelContentTests`

Expected: compilation fails because `SuperPanelFileSystemPresentation` and the `presentation` parameter do not exist, while the changed selected-folder expectation also disagrees with current folder actions.

- [ ] **Step 3: Add the explicit presentation context and minimal action switch**

```swift
public enum SuperPanelFileSystemPresentation: Equatable {
    case selectedItem
    case finderCurrentDirectory
}

public static func fileSystem(
    item: ClipboardItem,
    windowLayoutButtons: [WindowLayoutButton] = [],
    presentation: SuperPanelFileSystemPresentation = .selectedItem
) -> SuperPanelContent {
    let itemType = item.kind == .folder ? "文件夹" : "文件"
    let path = item.originalPath ?? item.displayTitle
    var actions: [SuperPanelActionDescriptor]

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
    actions.append(contentsOf: windowLayoutActionDescriptors(from: windowLayoutButtons))

    return SuperPanelContent(
        kind: .fileSystem,
        headerTitle: item.sourceApp?.isEmpty == false ? item.sourceApp! : "访达",
        headerSubtitle: item.displayTitle,
        headerSystemImage: item.kind == .folder ? "folder.fill" : "doc.fill",
        previewRows: [.init(label: itemType, value: path)],
        actions: actions
    )
}
```

- [ ] **Step 4: Thread the presentation through the AppKit controller**

Change the controller entry point to:

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
    show(content: content) { [weak self] actionID in
        self?.performFileAction(actionID, item: item, windowLayoutButtons: layoutButtons) ?? .close
    }
}
```

Change only the Finder-background call in `showFinderCurrentFolder` to:

```swift
contextPanel.show(item: item, presentation: .finderCurrentDirectory)
```

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run: `swift test --filter SuperPanelContentTests`

Expected: all `SuperPanelContentTests` pass; selected folders, files, and image files share the copy-path action, and Finder current directories retain three directory actions.

- [ ] **Step 6: Commit the context split**

```bash
git add Sources/MacToolsCore/UI/SuperPanelContent.swift Sources/MacTools/App/ContextPanelController.swift Sources/MacTools/App/AppEnvironment.swift Tests/MacToolsCoreTests/SuperPanelContentTests.swift
git commit -m "feat: unify selected file system actions"
```

---

### Task 2: Size Standard Layout Content Without Scrolling

**Files:**
- Modify: `Sources/MacToolsCore/UI/SuperPanelLayout.swift`
- Modify: `Sources/MacToolsCore/UI/ContextActionView.swift`
- Test: `Tests/MacToolsCoreTests/SuperPanelLayoutTests.swift`

**Interfaces:**
- Produces: `SuperPanelLayout.shouldScroll(for:) -> Bool`.
- Preserves: `SuperPanelLayout.panelSize(for:) -> CGSize`.
- Consumes: `ContextActionView` conditionally uses `ScrollView` only when `shouldScroll(for:)` is true.

- [ ] **Step 1: Add failing width, content-fit, and overflow-policy tests**

Use eight layout buttons for standard content and thirty for overflow content:

```swift
private func layoutButtons(count: Int) -> [WindowLayoutButton] {
    (0..<count).map {
        WindowLayoutButton(id: "layout.\($0)", title: "布局 \($0)", modes: [.maximize])
    }
}

private func makeItem(kind: ClipboardContentKind) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        kind: kind,
        displayTitle: kind == .folder ? "Project" : "notes.md",
        searchableText: "/Users/example/item",
        text: nil,
        originalPath: "/Users/example/item",
        cachedFilePath: nil,
        thumbnailPath: nil,
        sourceApp: "访达",
        createdAt: Date(timeIntervalSince1970: 0),
        lastUsedAt: nil,
        useCount: 0,
        isPinned: false,
        isFavorite: false
    )
}

func testStandardWindowLayoutPanelFitsWithoutScrolling() {
    let content = SuperPanelContent.windowLayoutOnly(windowLayoutButtons: layoutButtons(count: 8))
    XCTAssertEqual(SuperPanelLayout.panelSize(for: content), CGSize(width: 320, height: 313))
    XCTAssertFalse(SuperPanelLayout.shouldScroll(for: content))
}

func testSelectedFilePanelFitsWithoutScrolling() {
    let content = SuperPanelContent.fileSystem(
        item: makeItem(kind: .file),
        windowLayoutButtons: layoutButtons(count: 8)
    )
    XCTAssertEqual(SuperPanelLayout.panelSize(for: content), CGSize(width: 320, height: 404))
    XCTAssertFalse(SuperPanelLayout.shouldScroll(for: content))
}

func testFinderDirectoryPanelFitsWithoutScrolling() {
    let content = SuperPanelContent.fileSystem(
        item: makeItem(kind: .folder),
        windowLayoutButtons: layoutButtons(count: 8),
        presentation: .finderCurrentDirectory
    )
    XCTAssertEqual(SuperPanelLayout.panelSize(for: content), CGSize(width: 320, height: 518))
    XCTAssertFalse(SuperPanelLayout.shouldScroll(for: content))
}

func testOversizedCustomLayoutPanelUsesSafetyCapAndScrolling() {
    let content = SuperPanelContent.windowLayoutOnly(windowLayoutButtons: layoutButtons(count: 30))
    XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 620)
    XCTAssertTrue(SuperPanelLayout.shouldScroll(for: content))
}
```

- [ ] **Step 2: Run layout tests and verify RED**

Run: `swift test --filter SuperPanelLayoutTests`

Expected: tests fail because file-system/layout widths remain 260/250, heights remain half-scaled, and `shouldScroll(for:)` does not exist.

- [ ] **Step 3: Implement expanded content metrics**

Keep the existing text-panel calculation in a private helper. For `.fileSystem` and `.windowLayout`, calculate required height with these exact point metrics:

```swift
public static let expandedPanelWidth: CGFloat = 320
public static let expandedPanelMinimumHeight: CGFloat = 180
public static let expandedPanelMaximumHeight: CGFloat = 620

private static let headerAndDividerHeight: CGFloat = 59
private static let emptyPreviewHeight: CGFloat = 12
private static let previewRowHeight: CGFloat = 34
private static let previewVerticalPadding: CGFloat = 12
private static let sectionDividerHeight: CGFloat = 1
private static let actionSectionVerticalPadding: CGFloat = 16
private static let primaryActionRowHeight: CGFloat = 56
private static let actionDividerHeight: CGFloat = 1
private static let layoutHeaderHeight: CGFloat = 15
private static let layoutHeaderSpacing: CGFloat = 10
private static let layoutButtonHeight: CGFloat = 36
private static let layoutGridSpacing: CGFloat = 8
private static let layoutSectionVerticalPadding: CGFloat = 24
private static let contentFitSafetyPadding: CGFloat = 8
```

The required-height helper must sum preview rows, primary rows, the optional primary/layout divider, two-column layout rows, and safety padding. Then:

```swift
public static func shouldScroll(for content: SuperPanelContent) -> Bool {
    guard content.kind == .fileSystem || content.kind == .windowLayout else {
        return true
    }
    return expandedRequiredHeight(for: content) > expandedPanelMaximumHeight
}
```

`panelSize(for:)` returns width 320 and clamps expanded required height to `180...620`; text and text-transit content continue through the existing half-scale calculation.

- [ ] **Step 4: Remove the unconditional scroll view for standard content**

Extract the body content and switch on the policy:

```swift
@ViewBuilder
private var adaptiveBody: some View {
    if SuperPanelLayout.shouldScroll(for: content) {
        ScrollView {
            bodyContent
        }
    } else {
        bodyContent
    }
}

private var bodyContent: some View {
    VStack(spacing: 0) {
        previewSection
        Divider()
            .overlay(MacToolsGlassTheme.divider)
            .opacity(usesTextLayout ? 0.9 : 0.55)
        actionSection
    }
}
```

Replace `scrollableBody` in the main panel stack with `adaptiveBody`. Text panels keep scrolling available because their content can expand with translation length.

- [ ] **Step 5: Run layout and snapshot tests and verify GREEN**

Run: `swift test --filter 'SuperPanelLayoutTests|SuperPanelSnapshotTests'`

Expected: all focused layout and snapshot tests pass with 320-point file-system/layout snapshots and no standard-content scroll policy.

- [ ] **Step 6: Commit the content-fit layout**

```bash
git add Sources/MacToolsCore/UI/SuperPanelLayout.swift Sources/MacToolsCore/UI/ContextActionView.swift Tests/MacToolsCoreTests/SuperPanelLayoutTests.swift
git commit -m "fix: fit standard super panel layouts"
```

---

### Task 3: Update Verification Coverage And Launch The App

**Files:**
- Modify: `Tests/MacToolsCoreTests/SuperPanelSnapshotTests.swift`
- Modify: `docs/manual-verification.md`

**Interfaces:**
- Consumes: the selected-item presentation and content-fit size policy from Tasks 1 and 2.
- Produces: snapshot fixtures containing the standard eight layout buttons and an updated manual regression checklist.

- [ ] **Step 1: Expand the folder snapshot fixture to eight layouts**

Create eight `WindowLayoutButton` values in the snapshot test and pass them to the selected-folder `SuperPanelContent.fileSystem` call. The rendered snapshot must include the preview, `复制文件路径`, and all four two-column layout rows.

- [ ] **Step 2: Update manual verification wording**

Replace the prior selected-folder and compact-scroll checks with exact expectations:

```markdown
- In Finder with a selected file, folder, or image file, long right-click and confirm it shows `复制文件路径` followed by the complete configured window-layout list.
- Confirm file-system and window-layout-only panels use a 320 pt width and show the standard eight layout buttons without a scrollbar or clipped rows.
- In Finder with no selected item, confirm the current-directory actions remain `新建文件`, `复制当前路径`, and `在终端打开`, followed by the complete layout list.
```

- [ ] **Step 3: Run focused snapshots, full tests, and static checks**

Run:

```bash
snapshot_dir=$(mktemp -d /tmp/mactools-super-panel.XXXXXX)
MACTOOLS_SUPER_PANEL_SNAPSHOT_DIR="$snapshot_dir" swift test --filter SuperPanelSnapshotTests
swift test
git diff --check
```

Expected: snapshot test passes, all package tests pass with zero failures, and `git diff --check` prints no errors.

- [ ] **Step 4: Rebuild and launch the latest app**

Run: `scripts/rebuild_and_run_app.sh`

Expected: release build and signing succeed, the previous MacTools process stops, and `/Users/hanxun/code/mytools/build/MacTools.app` relaunches.

- [ ] **Step 5: Perform real-panel visual verification**

Trigger these live scenarios and capture screenshots:

1. A non-Finder app with no selection: all eight layout buttons are visible with no scrollbar.
2. Finder with a selected file or folder: `复制文件路径` and all eight layouts are visible.
3. Finder background: all three directory actions and all eight layouts are visible.
4. Place at least one panel over light content and one over dark content; inspect all four corners for gray outline, titlebar residue, rectangular shadow, or backing-layer leakage.

- [ ] **Step 6: Commit verification artifacts in source only**

Do not commit screenshots or generated app bundles. Commit the test fixture and checklist:

```bash
git add Tests/MacToolsCoreTests/SuperPanelSnapshotTests.swift docs/manual-verification.md
git commit -m "test: cover expanded super panel content"
```
