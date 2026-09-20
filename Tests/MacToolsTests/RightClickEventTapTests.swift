import AppKit
import MacToolsCore
import XCTest
@testable import MacTools

final class RightClickEventTapTests: XCTestCase {
    func testUnavailableTapFailsCleanlyAndStopIsIdempotent() {
        let tap = RightClickEventTap(thresholdMilliseconds: 250, logger: Logger(), createTap: { _, _, _ in nil }) { _ in
            XCTFail("Unavailable tap must not produce gestures")
        }
        XCTAssertFalse(tap.start())
        tap.stop()
        tap.stop()
    }

    /// 仅投递到测试进程本身，不向桌面或其他应用注入事件；需 WindowServer 与事件权限。
    @MainActor
    func testRealRunLoopTriggersWhileMainThreadIsBlockedAndReleasesTap() throws {
        guard ProcessInfo.processInfo.environment["MACTOOLS_EVENT_TAP_INTEGRATION"] == "1" else {
            throw XCTSkip("Opt-in WindowServer integration: MACTOOLS_EVENT_TAP_INTEGRATION=1")
        }
        _ = NSApplication.shared
        let observed = ObservedTapOutput()
        for _ in 0..<3 {
            let tap = RightClickEventTap(thresholdMilliseconds: 250, logger: Logger(), createTap: { mask, callback, info in
                CGEvent.tapCreateForPid(pid: getpid(), place: .headInsertEventTap, options: .defaultTap,
                    eventsOfInterest: mask, callback: callback, userInfo: info)
            }) { observed.append($0) }
            guard tap.start() else {
                XCTFail("Integration requires actual event-tap permission")
                return
            }
            defer { tap.stop() }
            let down = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown,
                mouseCursorPosition: .zero, mouseButton: .right))
            let up = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,
                mouseCursorPosition: .zero, mouseButton: .right))
            let before = observed.triggers
            down.postToPid(getpid())
            // 故意不泵主 RunLoop。事件线程必须独立完成拦截与一次性计时。
            Thread.sleep(forTimeInterval: 0.4)
            XCTAssertEqual(observed.triggers, before + 1)
            up.postToPid(getpid())
            tap.stop()
            tap.stop()
        }
    }
}

private final class ObservedTapOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var triggers: Int { lock.withLock { count } }
    func append(_ output: RightClickEventProcessor.Output) {
        if case .triggered = output { lock.withLock { count += 1 } }
    }
}
