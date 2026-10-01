import AppKit
import XCTest
@testable import MacTools
@testable import MacToolsCore

final class ApplicationShutdownCoordinatorTests: XCTestCase {
    @MainActor
    func testTerminationReplyWaitsForAcceptedSnapshotsToDrainAndLogsToFlush() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let writes = ShutdownWrites()
        let retry = ShutdownRetryClock()
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: ShutdownPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { item, _, _ in try writes.persist(item.text ?? "") }
        ), logger: logger, retryDelay: { _ in await retry.wait() })
        for index in 0..<2 {
            XCTAssertTrue(worker.enqueue(.init(payload: .init(text: "synthetic-\(index)"),
                sourceApp: "Tests", capturedAt: .distantPast, changeCount: index, skippedChangeCount: 0)))
        }
        await worker.start { _ in }
        await retry.waitUntilScheduled()
        var events: [String] = []
        let shutdown = ApplicationShutdownCoordinator(
            stop: { await worker.stop() },
            flush: { logger.flush(); events.append("flush") },
            reply: { events.append("reply") }
        )
        let delegate = AppDelegate(shutdownCoordinator: shutdown)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        XCTAssertEqual(events, [], "退出确认必须等已接受内容写入结束")
        writes.allowWrites()
        await retry.release()
        await shutdown.waitForCompletion()
        XCTAssertEqual(writes.values, ["synthetic-0", "synthetic-1"])
        XCTAssertEqual(events, ["flush", "reply"])
    }
}

private final class ShutdownWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = false
    private var records: [String] = []
    var values: [String] { lock.withLock { records } }
    func allowWrites() { lock.withLock { allowed = true } }
    func persist(_ text: String) throws {
        try lock.withLock {
            guard allowed else { throw NSError(domain: "SyntheticWriteFailure", code: 1) }
            records.append(text)
        }
    }
}

private final class ShutdownPasteboard: PasteboardClient {
    var changeCount: Int { 0 }
    func readPayload() -> ClipboardPayload { .init() }
}

private actor ShutdownRetryClock {
    private var continuation: CheckedContinuation<Void, Never>?
    private var scheduled: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            scheduled?.resume()
            scheduled = nil
        }
    }
    func waitUntilScheduled() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { scheduled = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

extension ApplicationShutdownCoordinatorTests {
    @MainActor
    func testRepeatedTerminationRequestsShareShutdownAndReplyOnce() async {
        let clock = ShutdownRetryClock()
        var stops = 0
        var flushes = 0
        var replies = 0
        let shutdown = ApplicationShutdownCoordinator(stop: {
            stops += 1
            await clock.wait()
        }, flush: { flushes += 1 }, reply: { replies += 1 })
        let delegate = AppDelegate(shutdownCoordinator: shutdown)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        await clock.waitUntilScheduled()
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateLater)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(flushes, 0)
        XCTAssertEqual(replies, 0)
        await clock.release()
        await shutdown.waitForCompletion()
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(flushes, 1)
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
        XCTAssertEqual(replies, 1)
    }

    @MainActor
    func testPersistentWriteFailureFinishesAfterRetryLimitBeforeReply() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let writes = ShutdownAttemptCount()
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: ShutdownPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { _, _, _ in writes.increment(); throw NSError(domain: "SyntheticWriteFailure", code: 1) }
        ), logger: logger, maximumAttempts: 3, retryDelay: { _ in })
        XCTAssertTrue(worker.enqueue(.init(payload: .init(text: "synthetic"), sourceApp: "Tests",
            capturedAt: .distantPast, changeCount: 1, skippedChangeCount: 0)))
        await worker.start { _ in }
        var replies = 0
        let shutdown = ApplicationShutdownCoordinator(stop: { await worker.stop() }, flush: { logger.flush() }, reply: {
            XCTAssertEqual(writes.value, 3)
            XCTAssertEqual(worker.status.count, 1)
            XCTAssertTrue(logger.messages.contains { $0.contains("pending snapshots: count=1") })
            replies += 1
        })
        XCTAssertEqual(shutdown.requestTermination(), .terminateLater)
        await shutdown.waitForCompletion()
        XCTAssertEqual(replies, 1)
        XCTAssertEqual(writes.value, 3)
    }
}

private final class ShutdownAttemptCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
