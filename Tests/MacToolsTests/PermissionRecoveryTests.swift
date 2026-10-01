import MacToolsCore
import XCTest
@testable import MacTools

@MainActor
final class PermissionRecoveryTests: XCTestCase {
    func testFailedStartStopsPartialTapResourcesExactlyOnce() {
        let tap = RecordingRightClickTap(installs: false)
        let monitor = makeMonitor { _ in tap }
        XCTAssertFalse(monitor.start())
        XCTAssertEqual(tap.stopCount, 1)
        monitor.stop()
        XCTAssertEqual(tap.stopCount, 1)
    }

    func testFailedTapIsRetriedWhenPermissionBecomesAvailable() {
        let taps = [RecordingRightClickTap(installs: false), RecordingRightClickTap(installs: true)]
        var index = 0
        let monitor = makeMonitor { _ in defer { index += 1 }; return taps[index] }
        XCTAssertFalse(monitor.start())
        monitor.refreshPermissions(.init(hasAccessibility: true, hasInputMonitoring: true))
        XCTAssertEqual(index, 2)
        XCTAssertEqual(taps[1].startCount, 1)
        monitor.stop()
    }

    func testValidTapIsRetainedAcrossRepeatedStartsAndPermissionRefreshes() {
        let tap = RecordingRightClickTap(installs: true)
        var creations = 0
        let monitor = makeMonitor { _ in creations += 1; return tap }
        XCTAssertTrue(monitor.start())
        for _ in 0..<5 {
            monitor.refreshPermissions(.init(hasAccessibility: true, hasInputMonitoring: true))
            XCTAssertTrue(monitor.start())
        }
        XCTAssertEqual(creations, 1)
        XCTAssertEqual(tap.startCount, 1)
        XCTAssertEqual(tap.stopCount, 0)
        monitor.stop()
    }

    func testRevocationStopsTapAndRestoredPermissionCreatesOneReplacement() {
        let tap = RecordingRightClickTap(installs: true)
        var creations = 0
        let monitor = makeMonitor { _ in creations += 1; return tap }
        XCTAssertTrue(monitor.start())
        monitor.refreshPermissions(.init(hasAccessibility: false, hasInputMonitoring: true))
        monitor.refreshPermissions(.init(hasAccessibility: false, hasInputMonitoring: true))
        XCTAssertEqual(tap.stopCount, 1)
        XCTAssertEqual(creations, 1)
        monitor.refreshPermissions(.init(hasAccessibility: true, hasInputMonitoring: true))
        XCTAssertEqual(creations, 2)
        XCTAssertEqual(tap.startCount, 2)
        monitor.stop()
    }

    func testInstalledButDisabledTapIsReplacedOnGrantedPermissionRefresh() {
        let taps = [RecordingRightClickTap(installs: true), RecordingRightClickTap(installs: true)]
        var index = 0
        let monitor = makeMonitor { _ in defer { index += 1 }; return taps[index] }
        XCTAssertTrue(monitor.start())
        taps[0].simulateDisabledTap()
        monitor.refreshPermissions(.init(hasAccessibility: true, hasInputMonitoring: true))
        XCTAssertEqual(index, 2)
        XCTAssertEqual(taps[0].stopCount, 1)
        XCTAssertEqual(taps[1].startCount, 1)
        monitor.stop()
    }

    private func makeMonitor(factory: @escaping (@escaping @Sendable (RightClickEventProcessor.Output) -> Void) -> any RightClickEventTapping) -> SuperRightClickMonitor {
        SuperRightClickMonitor(thresholdMilliseconds: 250,
            service: SuperRightClickService(settings: AppSettings.defaults.superRightClick,
                selectionCapture: EmptyPermissionSelection(), classifier: ClipboardClassifier(),
                translationService: TranslationService(provider: UnusedPermissionTranslation())),
            logger: Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            onGestureBegan: { _, _ in }, onCancelled: {}, onResultCaptured: { _, _ in },
            makeEventTap: factory, sourceApplication: { nil })
    }
}

private final class RecordingRightClickTap: RightClickEventTapping, @unchecked Sendable {
    let installs: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false
    init(installs: Bool) { self.installs = installs }
    func start() -> Bool { startCount += 1; isRunning = installs; return installs }
    func stop() { stopCount += 1; isRunning = false }
    func simulateDisabledTap() { isRunning = false }
}

private struct EmptyPermissionSelection: SelectionCapturing {
    func captureSelection() -> ClipboardPayload { ClipboardPayload() }
}

private struct UnusedPermissionTranslation: TranslationProvider {
    let providerID = "synthetic"
    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        XCTFail("Permission refresh must not translate")
        return .failure(.providerNotConfigured)
    }
}
