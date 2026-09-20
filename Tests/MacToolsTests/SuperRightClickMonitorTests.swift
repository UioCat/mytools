import AppKit
import MacToolsCore
import XCTest
@testable import MacTools

final class SuperRightClickMonitorTests: XCTestCase {
    @MainActor
    func testLateTranslationCannotReplaceNewGestureOrReopenAfterDismissalOrStop() async throws {
        for termination in ["newGesture", "dismiss", "stop"] {
            let provider = SuspendedRightClickTranslation()
            let firstResult = expectation(description: "initial capture")
            var translatedCount = 0
            let logger = Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            let monitor = SuperRightClickMonitor(
                thresholdMilliseconds: 250,
                service: SuperRightClickService(settings: AppSettings.defaults.superRightClick,
                    selectionCapture: SyntheticRightClickSelection(), classifier: ClipboardClassifier(),
                    translationService: TranslationService(provider: provider)),
                logger: logger, onGestureBegan: { _, _ in }, onCancelled: {},
                onResultCaptured: { result, _ in
                    if result.isTranslationPending { firstResult.fulfill() }
                    else { translatedCount += 1 }
                }
            )
            let id = UUID()
            monitor.handle(.began(id, atMilliseconds: 1_000))
            monitor.handle(.triggered(id))
            await fulfillment(of: [firstResult], timeout: 2)
            await provider.waitUntilStarted()
            let task = try XCTUnwrap(Mirror(reflecting: monitor).children.first { $0.label == "captureTask" }?.value as? Task<Void, Never>)
            switch termination {
            case "newGesture": monitor.handle(.began(UUID(), atMilliseconds: 2_000))
            case "dismiss": monitor.cancelCapture()
            default: monitor.stop()
            }
            await provider.finish()
            await task.value
            XCTAssertEqual(translatedCount, 0, termination)
            monitor.stop()
        }
    }

    @MainActor
    func testStopDuringSelectionCaptureDiscardsResultAndDoesNotStartTranslation() async throws {
        let started = expectation(description: "capture entered")
        let capture = BlockingRightClickSelection { started.fulfill() }
        let provider = SuspendedRightClickTranslation()
        var results = 0
        let monitor = SuperRightClickMonitor(thresholdMilliseconds: 250,
            service: SuperRightClickService(settings: AppSettings.defaults.superRightClick, selectionCapture: capture,
                classifier: ClipboardClassifier(), translationService: TranslationService(provider: provider)),
            logger: Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            onGestureBegan: { _, _ in }, onCancelled: {}, onResultCaptured: { _, _ in results += 1 })
        let id = UUID()
        monitor.handle(.began(id, atMilliseconds: 1_000))
        monitor.handle(.triggered(id))
        await fulfillment(of: [started], timeout: 2)
        let task = try XCTUnwrap(Mirror(reflecting: monitor).children.first { $0.label == "captureTask" }?.value as? Task<Void, Never>)
        monitor.stop()
        capture.release.signal()
        await task.value
        XCTAssertEqual(results, 0)
    }

    @MainActor
    func testCancelledTriggerDoesNotStartSelectionCapture() async {
        let capture = SyntheticRightClickSelection()
        let monitor = SuperRightClickMonitor(thresholdMilliseconds: 250,
            service: SuperRightClickService(settings: AppSettings.defaults.superRightClick, selectionCapture: capture,
                classifier: ClipboardClassifier(), translationService: TranslationService(provider: SuspendedRightClickTranslation())),
            logger: Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            onGestureBegan: { _, _ in }, onCancelled: {}, onResultCaptured: { _, _ in XCTFail("cancelled") })
        let id = UUID()
        monitor.handle(.began(id, atMilliseconds: 1_000))
        monitor.handle(.cancelled)
        monitor.handle(.triggered(id))
        await Task.yield()
        XCTAssertEqual(capture.count, 0)
    }
}

private final class BlockingRightClickSelection: SelectionCapturing, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    let started: @Sendable () -> Void
    init(started: @escaping @Sendable () -> Void) { self.started = started }
    func captureSelection() -> ClipboardPayload {
        started()
        _ = release.wait(timeout: .now() + 3)
        return ClipboardPayload(text: "Synthetic suspended capture")
    }
}

private final class SyntheticRightClickSelection: SelectionCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var captures = 0
    var count: Int { lock.withLock { captures } }
    func captureSelection() -> ClipboardPayload {
        lock.withLock { captures += 1 }
        return ClipboardPayload(text: "Synthetic right click regression")
    }
}

private actor SuspendedRightClickTranslation: TranslationProvider {
    nonisolated let providerID = "synthetic"
    private var continuation: CheckedContinuation<Result<TranslationResponse, TranslationError>, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() {
        continuation?.resume(returning: .success(TranslationResponse(translatedText: "synthetic result", providerID: providerID)))
        continuation = nil
    }
}
