import AppKit
import MacToolsCore
import XCTest
@testable import MacTools

final class ScreenCaptureCoordinatorTests: XCTestCase {
    @MainActor
    func testCancelledScreenshotCompletionCannotWriteOrDismissNewSession() async throws {
        let fixture = try CaptureFixture()
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 1 }
        fixture.overlay.select(fixture.selection, mode: .screenshot)
        await waitUntil { fixture.editor.completions.count == 1 }
        let completeA = fixture.editor.completions[0]

        fixture.overlay.cancel()
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 2 }
        fixture.overlay.select(fixture.selection, mode: .screenshot)
        await waitUntil { fixture.editor.completions.count == 2 }
        completeA(Data([1]))

        XCTAssertTrue(fixture.pasteboard.images.isEmpty, "A cancelled session cannot write its delayed PNG")
        XCTAssertTrue(fixture.overlay.isPresented, "A late completion cannot close session B")
        fixture.editor.completions[1](Data([2]))
        XCTAssertEqual(fixture.pasteboard.images, [Data([2])])
        XCTAssertFalse(fixture.overlay.isPresented)
    }

    @MainActor
    func testScreenshotCompletionIsAcceptedOnlyOnce() async throws {
        let fixture = try CaptureFixture()
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 1 }
        fixture.overlay.select(fixture.selection, mode: .screenshot)
        await waitUntil { fixture.editor.completions.count == 1 }
        let complete = fixture.editor.completions[0]
        complete(Data([3]))
        complete(Data([4]))
        XCTAssertEqual(fixture.pasteboard.images, [Data([3])])
    }

    @MainActor
    func testFailedScreenshotCopyDoesNotAcceptDelayedRetryFromOldEditor() async throws {
        let fixture = try CaptureFixture()
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 1 }
        fixture.overlay.select(fixture.selection, mode: .screenshot)
        await waitUntil { fixture.editor.completions.count == 1 }
        let complete = fixture.editor.completions[0]
        fixture.pasteboard.copyFails = true
        complete(Data([3]))
        XCTAssertEqual(fixture.failures.count, 1)
        fixture.pasteboard.copyFails = false
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 2 }
        complete(Data([4]))
        XCTAssertTrue(fixture.pasteboard.images.isEmpty)
        XCTAssertTrue(fixture.overlay.isPresented)
        fixture.overlay.cancel()
    }

    @MainActor
    func testCancelledRecordingKeepsNewRequestsBlockedUntilStartAndCleanupFinish() async throws {
        let fixture = try CaptureFixture()
        fixture.recorder.pauseStart = true
        fixture.recorder.pauseStop = true
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 1 }
        fixture.overlay.select(fixture.selection, mode: .recording)
        await waitUntil { fixture.recorder.startContinuation != nil }
        fixture.overlay.cancel()
        fixture.coordinator.start()
        await drainTasks()
        XCTAssertEqual(fixture.capture.captureCount, 1, "Starting resources remain exclusive after Escape")

        fixture.recorder.releaseStart()
        await waitUntil { fixture.recorder.stopContinuation != nil }
        fixture.coordinator.start()
        await drainTasks()
        XCTAssertEqual(fixture.capture.captureCount, 1, "File finalization also retains exclusivity")
        XCTAssertFalse(fixture.recordingControl.isPresented)
        fixture.recorder.releaseStop()
        await drainTasks()
        fixture.coordinator.start()
        await waitUntil { fixture.capture.captureCount == 2 }
        XCTAssertTrue(fixture.failures.isEmpty)
    }

    @MainActor
    func testRecordingStopIsAcceptedOnceAndKeepsResourcesExclusiveUntilSaved() async throws {
        let fixture = try CaptureFixture()
        fixture.recorder.pauseStop = true
        fixture.coordinator.start()
        await waitUntil { fixture.overlay.presentCount == 1 }
        fixture.overlay.select(fixture.selection, mode: .recording)
        await waitUntil { fixture.recordingControl.onStop != nil }
        let stop = try XCTUnwrap(fixture.recordingControl.onStop)
        stop()
        stop()
        await waitUntil { fixture.recorder.stopContinuation != nil }
        fixture.coordinator.start()
        XCTAssertEqual(fixture.capture.captureCount, 1)
        XCTAssertEqual(fixture.recorder.stopCount, 1)
        fixture.recorder.releaseStop()
        await drainTasks()
        XCTAssertEqual(fixture.revealed, [fixture.destination])
        XCTAssertTrue(fixture.failures.isEmpty)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected capture boundary was not reached", file: file, line: line)
    }

    @MainActor
    private func drainTasks() async {
        for _ in 0..<100 { await Task.yield() }
    }
}

@MainActor
private final class CaptureFixture {
    let selection = ScreenCaptureSelection(displayID: 7, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                           rawSelectionFrame: CGRect(x: 10, y: 10, width: 50, height: 50))
    let overlay = CaptureOverlay()
    let editor = CaptureEditor()
    let recordingControl = CaptureRecordingControl()
    let pasteboard = CapturePasteboard()
    let recorder = CaptureRecorder()
    let capture: CaptureStill
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    var failures: [String] = []
    var revealed: [URL] = []
    private(set) var coordinator: ScreenCaptureCoordinator!
    private let logDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let logger: Logger

    init() throws {
        logger = Logger(debugLogDirectory: logDirectory)
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        capture = CaptureStill(image: try XCTUnwrap(context.makeImage()))
        recorder.destination = destination
        coordinator = ScreenCaptureCoordinator(
            permissionService: PermissionService(checker: CapturePermissions()),
            logger: logger, stillCapture: capture, recorder: recorder,
            pasteboard: pasteboard, overlay: overlay, editor: editor, recordingControl: recordingControl,
            displaySelections: { [selection] in [ScreenCaptureSelection(displayID: selection.displayID,
                displayFrame: selection.displayFrame, rawSelectionFrame: selection.displayFrame)] },
            destinationProvider: { [destination] in destination },
            revealRecording: { [weak self] in self?.revealed.append($0) },
            failurePresenter: { [weak self] in self?.failures.append($0) })
    }

    deinit { logger.flush(); try? FileManager.default.removeItem(at: logDirectory) }
}

private struct CapturePermissions: PermissionChecking {
    func hasAccessibilityPermission() -> Bool { false }
    func hasInputMonitoringPermission() -> Bool { false }
    func hasPostEventPermission() -> Bool { false }
    func hasScreenRecordingPermission() -> Bool { true }
}

@MainActor
private final class CaptureStill: ScreenStillCapturing {
    let image: CGImage
    var captureCount = 0
    init(image: CGImage) { self.image = image }
    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage {
        captureCount += 1
        return image
    }
}

@MainActor
private final class CaptureOverlay: ScreenSelectionPresenting {
    var onSelection: ((ScreenCaptureSelection, ScreenCaptureMode) -> Void)?
    var onCancel: (() -> Void)?
    var presentCount = 0
    var isPresented = false
    func prepareForCapture(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func present(snapshots: [ScreenCaptureSnapshot],
                 onSelection: @escaping (ScreenCaptureSelection, ScreenCaptureMode) -> Void,
                 onCancel: @escaping () -> Void) {
        presentCount += 1
        isPresented = true
        self.onSelection = onSelection
        self.onCancel = onCancel
    }
    func presentEditor(_ editorView: NSView, for selection: ScreenCaptureSelection,
                       escapeHandler: @escaping (Bool) -> ScreenshotEditorEscapeAction) -> Bool { true }
    func dismiss() { isPresented = false; onSelection = nil; onCancel = nil }
    func select(_ selection: ScreenCaptureSelection, mode: ScreenCaptureMode) { onSelection?(selection, mode) }
    func cancel() { let handler = onCancel; dismiss(); handler?() }
}

@MainActor
private final class CaptureEditor: ScreenshotEditing {
    var completions: [(Data) -> Void] = []
    func prepare(image: CGImage, selection: ScreenCaptureSelection, settings: ScreenCaptureSettings,
                 onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
                 onCopy: @escaping (Data) -> Void, onCancel: @escaping () -> Void) { completions.append(onCopy) }
    func preparedContentView() -> NSView? { NSView(frame: .zero) }
    func handleEscape(hasMarkedText: Bool) -> ScreenshotEditorEscapeAction { .cancelSession }
    func dismiss() {}
}

@MainActor
private final class CaptureRecordingControl: RecordingControlPresenting {
    var onStop: (() -> Void)?
    var isPresented = false
    func show(selection: ScreenCaptureSelection, onStop: @escaping () -> Void) { self.onStop = onStop; isPresented = true }
    func hide() { isPresented = false; onStop = nil }
}

private final class CapturePasteboard: WritablePasteboard {
    var images: [Data] = []
    var copyFails = false
    func writeImageData(_ data: Data) throws {
        if copyFails { throw ScreenCaptureError.writerFailed }
        images.append(data)
    }
    func writeText(_ text: String) {}
    func writeFileURL(_ url: URL) {}
}

@MainActor
private final class CaptureRecorder: ScreenRecording {
    nonisolated var isRecording: Bool { false }
    var pauseStart = false
    var pauseStop = false
    var startContinuation: CheckedContinuation<Void, Never>?
    var stopContinuation: CheckedContinuation<Void, Never>?
    var stopCount = 0
    var destination: URL!
    func start(selection: ScreenCaptureSelection, destination: URL) async throws {
        if pauseStart { await withCheckedContinuation { startContinuation = $0 } }
    }
    func stop() async throws -> URL {
        stopCount += 1
        if pauseStop, stopCount == 1 { await withCheckedContinuation { stopContinuation = $0 } }
        return destination
    }
    func releaseStart() { let continuation = startContinuation; startContinuation = nil; continuation?.resume() }
    func releaseStop() { let continuation = stopContinuation; stopContinuation = nil; continuation?.resume() }
}
