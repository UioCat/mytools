import AppKit
import XCTest
@testable import MacTools
@testable import MacToolsCore

final class ApplicationWorkerRegressionTests: XCTestCase {
    func testAdmissionKeepsAcceptedPrefixWithinCountBudget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persisted = SnapshotRecords()
        let service = ClipboardService(
            pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(),
            settings: .defaults, persist: { item, _, _ in persisted.append(item.text ?? "") }
        )
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush() }
        let worker = ClipboardPollingWorker(service: service, logger: logger)
        for index in 0..<100 {
            worker.enqueue(ClipboardSnapshot(
                payload: .init(text: "synthetic-\(index)"), sourceApp: "Tests",
                capturedAt: .distantPast, changeCount: index, skippedChangeCount: 0
            ))
        }
        let firstBatch = expectation(description: "accepted prefix persisted")
        await worker.start { snapshot in
            if snapshot.changeCount == 63 { firstBatch.fulfill() }
        }
        await fulfillment(of: [firstBatch], timeout: 3)
        await worker.stop()
        XCTAssertEqual(persisted.values, (0..<64).map { "synthetic-\($0)" })
    }

    @MainActor
    func testFailedActivationDoesNotSendGlobalPaste() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush() }
        let target = InactivePasteTarget()
        let finished = expectation(description: "attempt finished")
        var pastes = 0
        let attempt = PasteActivationAttempt(
            targetApplication: target, notificationCenter: NotificationCenter(),
            logger: logger, paste: { pastes += 1 },
            onFinish: { _ in finished.fulfill() }
        )
        attempt.start()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(pastes, 0)
    }
}

private final class SnapshotRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String] = []
    var values: [String] { lock.withLock { records } }
    func append(_ text: String) { lock.withLock { records.append(text) } }
}

private final class WorkerRegressionPasteboard: PasteboardClient {
    var changeCount: Int { 0 }
    func readPayload() -> ClipboardPayload { .init() }
}

private final class InactivePasteTarget: NSRunningApplication, @unchecked Sendable {
    override var processIdentifier: pid_t { 123_456 }
    override var localizedName: String? { "Synthetic" }
    override var isActive: Bool { false }
    override var isTerminated: Bool { false }
    override func unhide() -> Bool { true }
    override func activate(options: NSApplication.ActivationOptions = []) -> Bool { false }
}

extension ApplicationWorkerRegressionTests {
    func testRetryDuringLastFailedWriteIsNotConsumedByThatFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let lastWriteEntered = expectation(description: "last automatic write is blocked")
        let recovered = expectation(description: "accepted snapshots drained after user retry")
        let state = RetryDuringFailureState(onBlockedWrite: { lastWriteEntered.fulfill() })
        defer { state.releaseFailedWrite() }
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { item, _, _ in try state.persist(item.text ?? "") }
        ), logger: logger, maximumAttempts: 2, retryDelay: { _ in })
        XCTAssertTrue(worker.enqueue(snapshot("first", index: 1)))
        XCTAssertTrue(worker.enqueue(snapshot("second", index: 2)))
        await worker.start { snapshot in
            if snapshot.changeCount == 2 { recovered.fulfill() }
        }
        await fulfillment(of: [lastWriteEntered], timeout: 2)
        XCTAssertTrue(worker.status.storagePaused)

        worker.retryPending()
        state.releaseFailedWrite()

        await fulfillment(of: [recovered], timeout: 2)
        await worker.stop()
        XCTAssertEqual(state.values, ["first", "second"])
        XCTAssertEqual(state.attempts, 4)
        XCTAssertEqual(worker.status.count, 0)
        XCTAssertFalse(worker.status.storagePaused)
    }

    func testInFlightSnapshotStillConsumesByteBudget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let entered = expectation(description: "writing")
        let release = DispatchSemaphore(value: 0)
        let records = SnapshotRecords()
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { item, _, _ in
                entered.fulfill()
                release.wait()
                records.append(item.text ?? "")
            }
        ), logger: logger, maximumCount: 2, maximumBytes: 10)
        XCTAssertTrue(worker.enqueue(snapshot("A", index: 1)))
        await worker.start { _ in }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertFalse(worker.enqueue(snapshot("B", index: 2)))
        XCTAssertEqual(worker.status.count, 1)
        XCTAssertEqual(worker.status.bytes, 6)
        XCTAssertTrue(worker.status.capacityPaused)
        release.signal()
        await worker.stop()
        XCTAssertEqual(records.values, ["A"])
        XCTAssertEqual(worker.status.bytes, 0)
    }

    func testFailureRetainsOrderAndRequiresExplicitRetryAfterLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let state = PersistenceState()
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { item, _, _ in try state.persist(item.text ?? "") }
        ), logger: logger, maximumCount: 3, maximumAttempts: 3, retryDelay: { _ in })
        for index in 0..<3 { XCTAssertTrue(worker.enqueue(snapshot("synthetic-\(index)", index: index))) }
        let failed = expectation(description: "storage paused")
        let recovered = expectation(description: "last item persisted")
        let failureSignal = SingleFailureSignal(failed)
        await worker.start(onStatusChange: { if worker.status.storagePaused { failureSignal.fulfill() } }) { snapshot in
            if snapshot.changeCount == 2 { recovered.fulfill() }
        }
        await fulfillment(of: [failed], timeout: 2)
        await worker.updateSettings(.defaults)
        XCTAssertEqual(state.attempts, 3)
        XCTAssertEqual(worker.status.count, 3)
        XCTAssertTrue(worker.status.capacityPaused)
        XCTAssertFalse(worker.enqueue(snapshot("new", index: 4)))
        state.allowWrites()
        worker.retryPending()
        await fulfillment(of: [recovered], timeout: 2)
        await worker.stop()
        XCTAssertEqual(state.values, (0..<3).map { "synthetic-\($0)" })
        XCTAssertFalse(worker.status.capacityPaused)
        XCTAssertFalse(worker.status.storagePaused)
    }

    func testOversizedSnapshotIsVisibleAndDoesNotBlockSmallerContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let records = SnapshotRecords()
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { item, _, _ in records.append(item.text ?? "") }
        ), logger: logger, maximumBytes: 8)
        XCTAssertFalse(worker.enqueue(snapshot("synthetic-large", index: 1)))
        XCTAssertNotNil(worker.status.warning)
        XCTAssertFalse(worker.status.isPaused)
        XCTAssertTrue(worker.enqueue(snapshot("A", index: 2)))
        await worker.start { _ in }
        await worker.stop()
        XCTAssertEqual(records.values, ["A"])
    }

    @MainActor
    func testCancelledDelayNeverPastesEvenIfClockIgnoresCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let target = ActivePasteTarget()
        let clock = PasteTestClock()
        var pastes = 0
        var finishes = 0
        let attempt = PasteActivationAttempt(targetApplication: target, notificationCenter: NotificationCenter(),
            logger: logger, paste: { pastes += 1 }, onFinish: { _ in finishes += 1 },
            frontmostApplication: { target }, delay: { _ in await clock.wait() })
        attempt.start()
        await clock.waitUntilScheduled()
        attempt.cancel()
        await clock.release()
        await Task.yield()
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(finishes, 1)
    }

    @MainActor
    func testFocusChangeOrTerminatedTargetPreventsPaste() async throws {
        for terminate in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let logger = Logger(debugLogDirectory: directory)
            defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
            let target = ActivePasteTarget()
            let other = ActivePasteTarget()
            let clock = PasteTestClock()
            let finished = expectation(description: "focus checked")
            var frontmost: NSRunningApplication? = target
            var pastes = 0
            let attempt = PasteActivationAttempt(targetApplication: target, notificationCenter: NotificationCenter(),
                logger: logger, paste: { pastes += 1 }, onFinish: { _ in finished.fulfill() },
                frontmostApplication: { frontmost }, delay: { _ in await clock.wait() })
            attempt.start()
            await clock.waitUntilScheduled()
            if terminate { target.simulatedTermination = true } else { frontmost = other }
            await clock.release()
            await fulfillment(of: [finished], timeout: 2)
            XCTAssertEqual(pastes, 0)
        }
    }

    @MainActor
    func testMatchingProcessIdentityPastesOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let target = ActivePasteTarget()
        let clock = PasteTestClock()
        let finished = expectation(description: "pasted")
        var pastes = 0
        let attempt = PasteActivationAttempt(targetApplication: target, notificationCenter: NotificationCenter(),
            logger: logger, paste: { pastes += 1 }, onFinish: { _ in finished.fulfill() },
            frontmostApplication: { target }, delay: { _ in await clock.wait() })
        attempt.start()
        await clock.waitUntilScheduled()
        await clock.release()
        await fulfillment(of: [finished], timeout: 2)
        attempt.cancel()
        XCTAssertEqual(pastes, 1)
    }

    private func snapshot(_ text: String, index: Int) -> ClipboardSnapshot {
        .init(payload: .init(text: text), sourceApp: "Tests", capturedAt: .distantPast,
              changeCount: index, skippedChangeCount: 0)
    }
}

private final class PersistenceState: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = false
    private var attemptCount = 0
    private var records: [String] = []
    var attempts: Int { lock.withLock { attemptCount } }
    var values: [String] { lock.withLock { records } }
    func allowWrites() { lock.withLock { allowed = true } }
    func persist(_ value: String) throws {
        try lock.withLock {
            attemptCount += 1
            guard allowed else { throw NSError(domain: "SyntheticWriteFailure", code: 1) }
            records.append(value)
        }
    }
}

private final class RetryDuringFailureState: @unchecked Sendable {
    private let lock = NSLock()
    private let failedWriteRelease = DispatchSemaphore(value: 0)
    private let onBlockedWrite: @Sendable () -> Void
    private var attemptCount = 0
    private var records: [String] = []

    init(onBlockedWrite: @escaping @Sendable () -> Void) { self.onBlockedWrite = onBlockedWrite }
    var attempts: Int { lock.withLock { attemptCount } }
    var values: [String] { lock.withLock { records } }
    func releaseFailedWrite() { failedWriteRelease.signal() }

    func persist(_ value: String) throws {
        let attempt = lock.withLock { attemptCount += 1; return attemptCount }
        if attempt == 2 {
            onBlockedWrite()
            _ = failedWriteRelease.wait(timeout: .now() + 3)
        }
        guard attempt > 2 else { throw NSError(domain: "SyntheticWriteFailure", code: 1) }
        lock.withLock { records.append(value) }
    }
}

private final class ActivePasteTarget: NSRunningApplication, @unchecked Sendable {
    var simulatedTermination = false
    override var processIdentifier: pid_t { 123_456 }
    override var isActive: Bool { true }
    override var isTerminated: Bool { simulatedTermination }
    override func unhide() -> Bool { true }
    override func activate(options: NSApplication.ActivationOptions = []) -> Bool { true }
    // 合成进程没有 AppKit 实例背后的启动身份；用对象身份模拟不同启动实例。
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ActivePasteTarget else { return false }
        return self === other
    }
    override var hash: Int { ObjectIdentifier(self).hashValue }
}

private actor PasteTestClock {
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

private final class SingleFailureSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var didFulfill = false
    private let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func fulfill() {
        lock.withLock {
            guard !didFulfill else { return }
            didFulfill = true
            expectation.fulfill()
        }
    }
}

extension ApplicationWorkerRegressionTests {
    func testStopCancelsRetryAndReportsRetainedAcceptedSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        let sleeping = expectation(description: "retry waiting")
        let state = PersistenceState()
        let worker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
            persist: { item, _, _ in try state.persist(item.text ?? "") }
        ), logger: logger, retryDelay: { _ in
            sleeping.fulfill()
            try await Task.sleep(for: .seconds(3_600))
        })
        XCTAssertTrue(worker.enqueue(snapshot("synthetic", index: 1)))
        await worker.start { _ in }
        await fulfillment(of: [sleeping], timeout: 2)
        await worker.stop(cancelPendingRetries: true)
        XCTAssertEqual(state.attempts, 1)
        XCTAssertEqual(worker.status.count, 1)
        XCTAssertTrue(worker.status.closed)
        XCTAssertFalse(worker.enqueue(snapshot("new", index: 2)))
        XCTAssertTrue(logger.messages.contains { $0.contains("pending snapshots: count=1") })
    }

    @MainActor
    func testMainActorNotificationsCoalesceProducerBurst() async {
        let first = expectation(description: "first notification")
        let second = expectation(description: "second notification")
        var calls = 0
        let notification = MainActorChangeNotification {
            calls += 1
            if calls == 1 { first.fulfill() }
            if calls == 2 { second.fulfill() }
        }
        for _ in 0..<5_000 { notification.signal() }
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(calls, 1)
        notification.signal()
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(calls, 2)
    }
}

extension ApplicationWorkerRegressionTests {
    func testStopReleasesEvenWhenStatusCallbackRetainsWorker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        weak var released: ClipboardPollingWorker?
        do {
            let worker = ClipboardPollingWorker(service: ClipboardService(
                pasteboard: WorkerRegressionPasteboard(), classifier: ClipboardClassifier(), settings: .defaults,
                persist: { _, _, _ in }
            ), logger: logger)
            released = worker
            await worker.start(onStatusChange: { _ = worker.status }) { _ in }
            await worker.stop()
        }
        XCTAssertNil(released)
    }
}

extension ApplicationWorkerRegressionTests {
    func testAdmissionPauseSkipsCopiesUntilNewCopyAfterRecovery() async {
        let pasteboard = SamplingTestPasteboard()
        let notificationCenter = NotificationCenter()
        let records = SnapshotRecords()
        let worker = ClipboardSamplingWorker(sampler: ClipboardSnapshotSampler(
            pasteboard: pasteboard, isRecordingEnabled: true
        ), notificationCenter: notificationCenter, frontmostApplicationName: { "Synthetic" })
        worker.start { records.append($0.payload.text ?? "") }
        await worker.waitUntilIdle()
        pasteboard.change(to: 1)
        notificationCenter.post(name: .macToolsPasteboardDidWrite, object: nil)
        await worker.waitUntilIdle()
        XCTAssertEqual(records.values, ["synthetic-1"])
        worker.setAdmissionPaused(true)
        await worker.waitUntilIdle()
        pasteboard.change(to: 2)
        notificationCenter.post(name: .macToolsPasteboardDidWrite, object: nil)
        await worker.waitUntilIdle()
        worker.setAdmissionPaused(false)
        await worker.waitUntilIdle()
        notificationCenter.post(name: .macToolsPasteboardDidWrite, object: nil)
        await worker.waitUntilIdle()
        XCTAssertEqual(records.values, ["synthetic-1"])
        pasteboard.change(to: 3)
        notificationCenter.post(name: .macToolsPasteboardDidWrite, object: nil)
        await worker.waitUntilIdle()
        worker.stop()
        await worker.waitUntilIdle()
        XCTAssertEqual(records.values, ["synthetic-1", "synthetic-3"])
    }
}

private final class SamplingTestPasteboard: PasteboardClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var changeCount: Int { lock.withLock { count } }
    func change(to value: Int) { lock.withLock { count = value } }
    func readPayload() -> ClipboardPayload { .init(text: "synthetic-\(changeCount)") }
}
