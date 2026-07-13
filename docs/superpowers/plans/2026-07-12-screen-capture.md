# 工具 3：框选截图与录屏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 将 Option+3 从预留动作变为单显示器框选截图与无声录屏，截图支持划线、箭头、矩形框和马赛克并复制到剪贴板，录屏保存 MP4 到 Downloads。

**Architecture:** MacToolsCore 承载选区、标注、会话状态、输出路径和权限规则；MacTools target 负责 AppKit 选区浮层、ScreenCaptureKit、AVAssetWriter、SwiftUI 编辑器与 Finder reveal。一个主线程 ScreenCaptureCoordinator 是单次会话的唯一所有者。

**Tech Stack:** Swift 5.10、macOS 26、AppKit、SwiftUI、ScreenCaptureKit、AVFoundation、Core Image、XCTest。

## Global Constraints

- 仅支持用户手动框选单个显示器区域；拖拽越界时夹取到起始显示器。
- 截图成功只写 PNG 到通用剪贴板，不调用 ClipboardService 或 ClipboardRepository。
- 录屏仅视频，不支持系统音频、麦克风、摄像头、全屏、窗口、GIF 或二次编辑；输出必须为 Downloads 下的 MP4。
- 所有临时采集面板必须 borderless、无系统阴影、透明背景和圆角裁切。
- 每个功能先写失败 XCTest，再写最小实现，任务结束运行 focused test。
- 最终必须运行 swift test、git diff --check、隐私扫描及 scripts/rebuild_and_run_app.sh。

---

### Task 1: Core selection, state and annotation history

**Files:**

- Create: Sources/MacToolsCore/ScreenCapture/ScreenCaptureSelection.swift
- Create: Sources/MacToolsCore/ScreenCapture/ScreenCaptureSession.swift
- Create: Sources/MacToolsCore/ScreenCapture/ScreenshotAnnotation.swift
- Create: Tests/MacToolsCoreTests/ScreenCaptureSelectionTests.swift
- Create: Tests/MacToolsCoreTests/ScreenCaptureSessionTests.swift
- Create: Tests/MacToolsCoreTests/ScreenshotAnnotationTests.swift

**Interfaces:**

- Produces ScreenCaptureSelection(displayID:displayFrame:rawSelectionFrame:), with frame and isValid.
- Produces ScreenCaptureSessionState, with beginSelection(), acceptSelection(_:), beginScreenshot(), beginRecording(), finish(), and cancel().
- Produces ordered ScreenshotAnnotationStore.

- [ ] **Step 1: Write failing tests**

~~~swift
func testSelectionNormalizesReverseDragAndClampsToOriginatingDisplay() {
    let selection = ScreenCaptureSelection(
        displayID: 7,
        displayFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
        rawSelectionFrame: CGRect(x: 950, y: 750, width: -900, height: -700)
    )

    XCTAssertEqual(selection.frame, CGRect(x: 100, y: 100, width: 800, height: 600))
    XCTAssertTrue(selection.isValid)
}

func testSessionCannotStartRecordingWithoutAValidSelection() {
    var state = ScreenCaptureSessionState.idle

    XCTAssertFalse(state.beginRecording())
    XCTAssertEqual(state, .idle)
}

func testAnnotationStoreUndoesLatestMosaicOnly() {
    var store = ScreenshotAnnotationStore()
    let arrow = ScreenshotAnnotation.arrow(start: .zero, end: CGPoint(x: 10, y: 10))
    let mosaic = ScreenshotAnnotation.mosaic(CGRect(x: 1, y: 1, width: 8, height: 8))
    store.append(arrow)
    store.append(mosaic)

    XCTAssertEqual(store.undo(), mosaic)
    XCTAssertEqual(store.annotations, [arrow])
}
~~~

- [ ] **Step 2: Verify red**

Run: swift test --filter 'ScreenCaptureSelectionTests|ScreenCaptureSessionTests|ScreenshotAnnotationTests'

Expected: FAIL because the capture model types are undefined.

- [ ] **Step 3: Implement the smallest Core model**

~~~swift
import CoreGraphics

public struct ScreenCaptureSelection: Equatable {
    public static let minimumSideLength: CGFloat = 8
    public let displayID: UInt32
    public let displayFrame: CGRect
    public let rawSelectionFrame: CGRect

    public init(displayID: UInt32, displayFrame: CGRect, rawSelectionFrame: CGRect) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.rawSelectionFrame = rawSelectionFrame
    }

    public var frame: CGRect {
        rawSelectionFrame.standardized.intersection(displayFrame).integral
    }

    public var isValid: Bool {
        frame.width >= Self.minimumSideLength && frame.height >= Self.minimumSideLength
    }
}

public enum ScreenshotAnnotation: Equatable {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)
    case mosaic(CGRect)
}

public struct ScreenshotAnnotationStore: Equatable {
    public private(set) var annotations: [ScreenshotAnnotation] = []
    public init() {}
    public mutating func append(_ annotation: ScreenshotAnnotation) { annotations.append(annotation) }
    @discardableResult public mutating func undo() -> ScreenshotAnnotation? { annotations.popLast() }
}

public enum ScreenCaptureSessionState: Equatable {
    case idle, selecting, selectionReady(ScreenCaptureSelection), capturingScreenshot
    case editingScreenshot, recording(ScreenCaptureSelection), finished, cancelled, failed

    public mutating func beginSelection() { self = .selecting }
    public mutating func acceptSelection(_ selection: ScreenCaptureSelection) -> Bool {
        guard selection.isValid else { return false }
        self = .selectionReady(selection)
        return true
    }
    public mutating func beginScreenshot() -> Bool {
        guard case .selectionReady = self else { return false }
        self = .capturingScreenshot
        return true
    }
    public mutating func beginRecording() -> Bool {
        guard case let .selectionReady(selection) = self else { return false }
        self = .recording(selection)
        return true
    }
    public mutating func finish() { self = .finished }
    public mutating func cancel() { self = .cancelled }
}
~~~

- [ ] **Step 4: Verify green**

Run: swift test --filter 'ScreenCaptureSelectionTests|ScreenCaptureSessionTests|ScreenshotAnnotationTests'

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add Sources/MacToolsCore/ScreenCapture Tests/MacToolsCoreTests/ScreenCaptureSelectionTests.swift Tests/MacToolsCoreTests/ScreenCaptureSessionTests.swift Tests/MacToolsCoreTests/ScreenshotAnnotationTests.swift
git commit -m "feat: add screen capture core state"
~~~

### Task 2: Downloads target and capture permission

**Files:**

- Create: Sources/MacToolsCore/ScreenCapture/RecordingDestinationResolver.swift
- Create: Tests/MacToolsCoreTests/RecordingDestinationResolverTests.swift
- Modify: Sources/MacToolsCore/Permissions/PermissionService.swift
- Modify: Tests/MacToolsCoreTests/PermissionServiceTests.swift
- Modify: Sources/MacToolsCore/UI/SettingsView.swift

**Interfaces:**

- Produces RecordingDestinationResolver.nextURL() throws -> URL.
- Adds screenRecording to AppPermission, hasScreenRecording to PermissionSummary, and request/check methods to PermissionChecking.

- [ ] **Step 1: Write failing tests**

~~~swift
func testDestinationUsesDownloadsAndIncrementsExistingFilename() throws {
    let directory = try makeTemporaryDirectory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let timestamp = try XCTUnwrap(calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 12,
        hour: 10,
        minute: 30
    )))
    let resolver = RecordingDestinationResolver(
        directory: directory,
        now: timestamp,
        timeZone: calendar.timeZone
    )
    let first = try resolver.nextURL()
    try Data().write(to: first)

    XCTAssertEqual(first.lastPathComponent, "MacTools Recording 2026-07-12 10.30.00.mp4")
    XCTAssertEqual(try resolver.nextURL().lastPathComponent, "MacTools Recording 2026-07-12 10.30.00 2.mp4")
}

func testScreenRecordingPermissionIsIncludedInSummaryAndSettingsURL() {
    let summary = PermissionService(checker: FakePermissionChecker(screenRecording: false)).summary()

    XCTAssertFalse(summary.hasScreenRecording)
    XCTAssertEqual(
        PermissionService.systemSettingsURL(for: .screenRecording),
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    )
}
~~~

- [ ] **Step 2: Verify red**

Run: swift test --filter 'RecordingDestinationResolverTests|PermissionServiceTests'

Expected: FAIL because the resolver and screen-recording permission are missing.

- [ ] **Step 3: Implement output and permission support**

~~~swift
public struct RecordingDestinationResolver {
    public let directory: URL
    public let now: Date
    public let timeZone: TimeZone

    public init(directory: URL, now: Date = .now, timeZone: TimeZone = .current) {
        self.directory = directory
        self.now = now
        self.timeZone = timeZone
    }

    public func nextURL(fileManager: FileManager = .default) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stem = "MacTools Recording \(formatter.string(from: now))"
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = directory.appendingPathComponent("\(stem)\(suffix).mp4")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
~~~

Add hasScreenRecordingPermission() and requestScreenRecordingPermission() requirements, using CGPreflightScreenCaptureAccess() and CGRequestScreenCaptureAccess() in SystemPermissionChecker. Add the field to every PermissionSummary initializer and show a PermissionStatusRow titled 屏幕与系统音频录制 in settings.

- [ ] **Step 4: Verify green**

Run: swift test --filter 'RecordingDestinationResolverTests|PermissionServiceTests'

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add Sources/MacToolsCore/ScreenCapture/RecordingDestinationResolver.swift Sources/MacToolsCore/Permissions/PermissionService.swift Sources/MacToolsCore/UI/SettingsView.swift Tests/MacToolsCoreTests/RecordingDestinationResolverTests.swift Tests/MacToolsCoreTests/PermissionServiceTests.swift
git commit -m "feat: add capture permission and recording destination"
~~~

### Task 3: Tool-three routing and display-local selection overlay

**Files:**

- Create: Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift
- Create: Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift
- Modify: Sources/MacTools/App/MenuBarController.swift
- Modify: Sources/MacTools/App/AppDelegate.swift
- Modify: Sources/MacTools/App/AppEnvironment.swift
- Modify: Sources/MacToolsCore/HotKeys/HotKey.swift
- Modify: Sources/MacToolsCore/HotKeys/HotKeyService.swift
- Modify: Sources/MacToolsCore/UI/SettingsView.swift
- Modify: Tests/MacToolsCoreTests/HotKeyServiceTests.swift

**Interfaces:**

- ScreenSelectionOverlayController.present(onSelection:onCancel:) sends one valid selection or cancellation.
- ScreenCaptureCoordinator.start() preflights permission, opens selection, then exposes screenshot/recording mode controls; system UI integration is covered by manual verification because the SwiftPM test target imports MacToolsCore, not the executable App target.
- AppEnvironment.openScreenCapture() is the only AppDelegate entry point.

- [ ] **Step 1: Write failing tests**

~~~swift
func testToolThreeBindingRepresentsScreenCapture() {
    let service = HotKeyService(registrar: FakeHotKeyRegistrar())
    service.configure(settings: .defaults)

    XCTAssertEqual(service.binding(for: "Option+3"), .screenCapture)
}
~~~

- [ ] **Step 2: Verify red**

Run: swift test --filter HotKeyServiceTests

Expected: FAIL due to missing screenCapture.

- [ ] **Step 3: Implement routing and overlay**

~~~swift
public enum HotKeyTarget: Equatable {
    case mainPanel, clipboard, translation, screenCapture, windowLayout(WindowLayoutMode)
}

@MainActor
final class ScreenCaptureCoordinator {
    func start() {
        guard permission.requestIfNeeded() else {
            presenter.showPermissionRequired()
            return
        }
        overlay.present(
            onSelection: { [weak self] selection in self?.presentModeMenu(for: selection) },
            onCancel: { [weak self] in self?.cancel() }
        )
    }
}
~~~

For each NSScreen, create a panel with styleMask [.borderless, .nonactivatingPanel], isOpaque false, backgroundColor clear, hasShadow false, level screenSaver, and a rounded layer-backed content view. Start the drag only inside its owning panel; convert its local positions using screen.frame and construct ScreenCaptureSelection from the panel NSScreenNumber display ID. The mode toolbar contains only 截图 and 录屏, with Esc cancellation.

Change visible settings title 工具 3 to 截图与录屏; retain reservedTool3Shortcut in persisted settings. In AppDelegate, map screenCapture to environment.openScreenCapture(), and expose the same action from the menu bar menu.

- [ ] **Step 4: Verify green**

Run: swift test --filter HotKeyServiceTests

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add Sources/MacTools/App/AppDelegate.swift Sources/MacTools/App/AppEnvironment.swift Sources/MacTools/App/ScreenCapture Sources/MacToolsCore/HotKeys Sources/MacToolsCore/UI/SettingsView.swift Tests/MacToolsCoreTests/HotKeyServiceTests.swift
git commit -m "feat: open capture selection from tool three"
~~~

### Task 4: Capture, annotate, and copy a screenshot

**Files:**

- Create: Sources/MacTools/App/ScreenCapture/SystemScreenCaptureService.swift
- Create: Sources/MacToolsCore/ScreenCapture/ScreenshotRenderer.swift
- Create: Sources/MacTools/App/ScreenCapture/ScreenshotEditorPanelController.swift
- Create: Sources/MacTools/App/ScreenCapture/ScreenshotEditorView.swift
- Create: Tests/MacToolsCoreTests/ScreenshotRendererTests.swift
- Modify: Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift

**Interfaces:**

- ScreenStillCapturing.capture(selection:) async throws -> CGImage.
- ScreenshotRenderer.pngData(image:annotations:) throws -> Data.
- ScreenshotEditorPanelController.present(image:onCopy:onCancel:).

- [ ] **Step 1: Write failing tests**

~~~swift
func testRendererProducesAPNGWhenGivenRectangleAndMosaic() throws {
    let data = try ScreenshotRenderer.pngData(
        image: sampleCGImage,
        annotations: [
            .rectangle(CGRect(x: 1, y: 1, width: 4, height: 4)),
            .mosaic(CGRect(x: 5, y: 5, width: 4, height: 4))
        ]
    )

    XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}

~~~

- [ ] **Step 2: Verify red**

Run: swift test --filter ScreenshotRendererTests

Expected: FAIL due to missing renderer API.

- [ ] **Step 3: Implement ScreenCaptureKit and renderer**

~~~swift
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
    throw ScreenCaptureError.displayUnavailable
}
let filter = SCContentFilter(display: display, excludingApplications: [ownApplication], exceptingWindows: [])
let configuration = SCStreamConfiguration()
let sourceRect = selection.frame.offsetBy(dx: -selection.displayFrame.minX, dy: -selection.displayFrame.minY)
configuration.sourceRect = sourceRect
configuration.width = Int(sourceRect.width * scale)
configuration.height = Int(sourceRect.height * scale)
let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
~~~

Use a bitmap CGContext to draw the original image. For each annotation, draw an arrow or rectangle with a blue CGColor, or crop a CIFilter.pixellate() result to the mosaic rectangle and composite it. Encode final CGImage using CGImageDestinationCreateWithData and kUTTypePNG. The SwiftUI editor stores annotations in State, maps gestures from fitted-image coordinates to pixels, handles Command+Z, and invokes SystemWritablePasteboard.writeImageData(_:) only from its 完成 action.

- [ ] **Step 4: Verify green**

Run: swift test --filter ScreenshotRendererTests

Expected: PASS.

- [ ] **Step 5: Commit**

~~~bash
git add Sources/MacTools/App/ScreenCapture Sources/MacToolsCore/ScreenCapture/ScreenshotRenderer.swift Tests/MacToolsCoreTests/ScreenshotRendererTests.swift
git commit -m "feat: add annotated screenshot capture"
~~~

### Task 5: Record the selection and reveal its MP4

**Files:**

- Create: Sources/MacTools/App/ScreenCapture/MP4ScreenRecorder.swift
- Create: Sources/MacTools/App/ScreenCapture/RecordingControlPanelController.swift
- Modify: Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift
- Modify: Tests/MacToolsCoreTests/ScreenCaptureSessionTests.swift
- Modify: docs/manual-verification.md

**Interfaces:**

- ScreenRecording.start(selection:destination:) async throws and stop() async throws -> URL.
- FinderRevealing.reveal(_:).
- RecordingControlPanelController.show(selection:onStop:).

- [ ] **Step 1: Write failing tests**

~~~swift
func testRecordingStateTransitionsToFinishedWhenStopped() {
    var state = ScreenCaptureSessionState.idle
    let selection = ScreenCaptureSelection(
        displayID: 7,
        displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        rawSelectionFrame: CGRect(x: 10, y: 10, width: 40, height: 40)
    )
    XCTAssertTrue(state.acceptSelection(selection))
    XCTAssertTrue(state.beginRecording())

    state.finish()

    XCTAssertEqual(state, .finished)
}
~~~

- [ ] **Step 2: Verify red**

Run: swift test --filter ScreenCaptureSessionTests

Expected: FAIL because recording session completion is absent.

- [ ] **Step 3: Implement MP4 recording and stop control**

~~~swift
final class MP4ScreenRecorder: NSObject, ScreenRecording, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func stop() async throws -> URL {
        try await stream.stopCapture()
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ScreenCaptureError.writerFailed }
        return destination
    }
}
~~~

Create the capture stream with the same display/source rect as Task 4, minimumFrameInterval = CMTime(value: 1, timescale: 30), and showsCursor true. Use H.264 AVAssetWriterInput with the capture pixel dimensions. No audio stream output or audio writer input is permitted. The stop control has a red button, elapsed time, an accessibility label, and a once-only stop closure. On writer failure, remove the partial destination URL. On successful stop, call NSWorkspace.shared.activateFileViewerSelecting([url]).

- [ ] **Step 4: Verify green**

Run: swift test --filter ScreenCaptureSessionTests

Expected: PASS.

- [ ] **Step 5: Update manual verification and commit**

Add a 截图与录屏 checklist covering denied permission, one-display box selection, cancel, copy of all three annotation types, playable MP4 under Downloads, ignored re-trigger while recording, and light/dark no-gray-edge inspection.

~~~bash
git add Sources/MacTools/App/ScreenCapture Tests/MacToolsCoreTests/ScreenCaptureSessionTests.swift docs/manual-verification.md
git commit -m "feat: record selected screen region to downloads"
~~~

### Task 6: Full verification

**Files:**

- Modify only exact affected source/test files if verification exposes a defect.

- [ ] **Step 1: Run automated verification**

Run: swift test && git diff --check

Expected: full suite passes and whitespace check is clean.

- [ ] **Step 2: Run privacy scan**

~~~bash
rg -n --hidden --glob '!.git/**' --glob '!.worktrees/**' --glob '!.build/**' --glob '!build/**' -i 'api[_ -]?key|access[_ -]?key|secret|token|password|credential|private[_ -]?key|client[_ -]?secret|app[_ -]?secret|authorization|bearer|cookie|session'
~~~

Expected: all hits are reviewed and no newly committed credentials exist.

- [ ] **Step 3: Launch and visually verify**

Run: scripts/rebuild_and_run_app.sh

Expected: MacTools launches; inspect selection overlay, screenshot editor, and recording control over light and dark backgrounds, then execute the new manual checklist.
