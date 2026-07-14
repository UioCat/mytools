# Super Right-Click Context Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show layout-only actions for empty application selections, directory actions for Finder background/folders, and copy-path-only actions for selected files.

**Architecture:** Carry a stable frontmost-application context through capture results and route presentation in `MacToolsCore`. Resolve the active Finder directory through Accessibility in a focused service, while keeping AppKit panel presentation in `ContextPanelController` and `AppEnvironment`.

**Tech Stack:** Swift 6, AppKit, ApplicationServices Accessibility, SwiftUI, Swift Package Manager, XCTest

## Global Constraints

- Selected text and URL behavior remains unchanged and contains no layout actions.
- Empty non-Finder context shows only configured window-layout actions.
- Finder background and selected folders show `新建文件`, `复制当前路径`, `在终端打开`, then layout actions.
- Selected files and image files show `复制文件路径`, then layout actions.
- Finder identity uses bundle identifier `com.apple.finder`, not localized display name.
- Finder path failures degrade to the layout-only panel without using stale clipboard data.
- Preserve the borderless/no-shadow/rounded-clipping panel policy and run `scripts/rebuild_and_run_app.sh`.

---

### Task 1: Source application context and presentation router

**Files:**
- Create: `Sources/MacToolsCore/RightClick/SuperRightClickPresentationRouter.swift`
- Modify: `Sources/MacToolsCore/RightClick/SuperRightClickService.swift`
- Modify: `Sources/MacTools/App/SuperRightClickMonitor.swift`
- Modify: `Tests/MacToolsCoreTests/RightClickStateMachineTests.swift`

**Interfaces:**
- Produces: `SuperRightClickSourceApplication`, `SuperRightClickPresentationRoute`, and `SuperRightClickPresentationRouter.route(for:)`.
- Changes: `SuperRightClickService.handleDecision(_:sourceApplication:)` replaces the source-name-only parameter.

- [ ] **Step 1: Write failing routing tests**

Add tests proving:

```swift
let notes = SuperRightClickSourceApplication(
    localizedName: "Notes",
    bundleIdentifier: "com.apple.Notes",
    processIdentifier: 42
)
let finder = SuperRightClickSourceApplication(
    localizedName: "访达",
    bundleIdentifier: "com.apple.finder",
    processIdentifier: 43
)

XCTAssertEqual(route(kind: .unknown, source: notes), .windowLayoutOnly)
XCTAssertEqual(route(kind: .imageData, source: notes), .windowLayoutOnly)
XCTAssertEqual(route(kind: .unknown, source: finder), .finderCurrentFolder)
XCTAssertEqual(route(kind: .text, source: notes), .text)
XCTAssertEqual(route(kind: .file, source: finder), .fileSystem)
XCTAssertEqual(route(kind: .folder, source: finder), .fileSystem)
```

Update service tests to pass `sourceApplication:` and assert the result preserves all three source fields while the classified item keeps the localized source name.

- [ ] **Step 2: Run RED**

Run: `swift test --filter 'SuperRightClickPresentationRouterTests|SuperRightClickServiceTests'`

Expected: FAIL because the source context and router do not exist and the service still accepts `sourceApp:`.

- [ ] **Step 3: Implement source context and router**

```swift
public struct SuperRightClickSourceApplication: Equatable {
    public var localizedName: String?
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?

    public var isFinder: Bool { bundleIdentifier == "com.apple.finder" }
}

public enum SuperRightClickPresentationRoute: Equatable {
    case text
    case fileSystem
    case finderCurrentFolder
    case windowLayoutOnly
}
```

Route text/URL to `.text`, file/folder/imageFile to `.fileSystem`, and empty/image-data content according to `sourceApplication.isFinder`.

Add `sourceApplication` to `SuperRightClickResult`. Update the monitor to capture `NSWorkspace.shared.frontmostApplication` name, bundle identifier, and PID at long-press time.

- [ ] **Step 4: Run GREEN**

Run: `swift test --filter 'SuperRightClickPresentationRouterTests|SuperRightClickServiceTests'`

Expected: all routing/service tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/RightClick/SuperRightClickPresentationRouter.swift Sources/MacToolsCore/RightClick/SuperRightClickService.swift Sources/MacTools/App/SuperRightClickMonitor.swift Tests/MacToolsCoreTests/RightClickStateMachineTests.swift
git commit -m "feat: route super right click by application context"
```

### Task 2: Directory, file, and layout-only panel content

**Files:**
- Modify: `Sources/MacToolsCore/UI/SuperPanelContent.swift`
- Modify: `Sources/MacTools/App/ContextPanelController.swift`
- Modify: `Tests/MacToolsCoreTests/SuperPanelContentTests.swift`

**Interfaces:**
- Produces: exact directory/file action lists and `ContextPanelController.showWindowLayoutOnly()`.

- [ ] **Step 1: Change content tests to the new action contracts**

Folder expectation:

```swift
XCTAssertEqual(content.actions.map(\.id), [.createNewFile, .copyPath, .openTerminal])
XCTAssertEqual(content.actions.map(\.title), ["新建文件", "复制当前路径", "在终端打开"])
```

File expectation:

```swift
XCTAssertEqual(content.actions.map(\.id), [.copyPath])
XCTAssertEqual(content.actions.map(\.title), ["复制文件路径"])
```

Keep the existing test proving layout buttons append after primary actions.

- [ ] **Step 2: Run RED**

Run: `swift test --filter SuperPanelContentTests`

Expected: folder and file action-list tests fail against the old Claude/Finder actions.

- [ ] **Step 3: Implement minimal content and panel changes**

Change `SuperPanelContent.fileSystem` to the exact action/title lists above, followed by `windowLayoutActionDescriptors`.

Add:

```swift
func showWindowLayoutOnly() {
    let layoutButtons = windowLayoutButtons()
    let content = SuperPanelContent.windowLayoutOnly(windowLayoutButtons: layoutButtons)
    show(content: content) { [weak self] actionID in
        guard case .windowLayoutButton(let id) = actionID else { return .close }
        return self?.performWindowLayoutAction(id, buttons: layoutButtons) ?? .close
    }
}
```

- [ ] **Step 4: Run GREEN**

Run: `swift test --filter SuperPanelContentTests`

Expected: all content tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacToolsCore/UI/SuperPanelContent.swift Sources/MacTools/App/ContextPanelController.swift Tests/MacToolsCoreTests/SuperPanelContentTests.swift
git commit -m "feat: tailor super panel actions by item type"
```

### Task 3: Finder current-folder resolver and runtime integration

**Files:**
- Create: `Sources/MacToolsCore/RightClick/FinderCurrentFolderResolver.swift`
- Create: `Tests/MacToolsCoreTests/FinderCurrentFolderResolverTests.swift`
- Modify: `Sources/MacTools/App/AppEnvironment.swift`
- Modify: `docs/manual-verification.md`

**Interfaces:**
- Produces: `FinderCurrentFolderResolving.currentFolderURL(processIdentifier:)` and `SystemFinderCurrentFolderResolver`.
- Consumes: `SuperRightClickPresentationRouter`, `ContextPanelController.show(item:)`, and `showWindowLayoutOnly()`.

- [ ] **Step 1: Write failing URL parser tests**

```swift
XCTAssertEqual(
    FinderDocumentURLParser.fileURL(from: "fixtures/My%20Project/"),
    URL(fileURLWithPath: "fixtures/My Project", isDirectory: true)
)
XCTAssertEqual(
    FinderDocumentURLParser.fileURL(from: "fixtures/Project"),
    URL(fileURLWithPath: "fixtures/Project", isDirectory: true)
)
XCTAssertNil(FinderDocumentURLParser.fileURL(from: "https://example.com"))
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter FinderCurrentFolderResolverTests`

Expected: FAIL because the parser/resolver do not exist.

- [ ] **Step 3: Implement the resolver**

Use `AXUIElementCreateApplication(processIdentifier)`, `kAXFocusedWindowAttribute`, and `kAXDocumentAttribute`. Parse file URLs and absolute paths with `FinderDocumentURLParser`. Return the user's Desktop directory when Finder has no focused window; return `nil` for invalid/missing document values.

- [ ] **Step 4: Route runtime presentation**

In `AppEnvironment.handleSuperRightClickResult`, switch on `SuperRightClickPresentationRouter.route(for:)`:

- `.text`: existing text presentation.
- `.fileSystem`: existing item presentation.
- `.windowLayoutOnly`: call `contextPanel.showWindowLayoutOnly()`.
- `.finderCurrentFolder`: resolve the active Finder directory using the captured PID, build a folder `ClipboardItem`, and show it. On failure log and call `showWindowLayoutOnly()`.

Update `docs/manual-verification.md` with the three requested contexts and the existing gray-edge check.

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter 'FinderCurrentFolderResolverTests|SuperRightClickPresentationRouterTests|SuperPanelContentTests'`

Expected: all focused tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacToolsCore/RightClick/FinderCurrentFolderResolver.swift Sources/MacTools/App/AppEnvironment.swift Tests/MacToolsCoreTests/FinderCurrentFolderResolverTests.swift docs/manual-verification.md
git commit -m "feat: show Finder directory actions without selection"
```

### Task 4: Full verification and local launch

**Files:**
- No source changes expected.

- [ ] **Step 1: Run full tests and hygiene checks**

```bash
swift test
git diff --check
git status --short
```

Expected: all tests pass, no whitespace errors, clean project worktree.

- [ ] **Step 2: Run the required privacy scan**

Run the command from `AGENTS.md` and confirm no new credentials appear in this change.

- [ ] **Step 3: Rebuild and launch**

Run: `scripts/rebuild_and_run_app.sh`

Expected: release build, signing, process replacement, and launch succeed.

- [ ] **Step 4: Visual verification**

Check application-empty, Finder-background, selected-folder, and selected-file panels over contrasting backgrounds. Confirm action order, layout visibility, scrolling, and no gray outline/titlebar/system shadow outside the rounded glass surface.
