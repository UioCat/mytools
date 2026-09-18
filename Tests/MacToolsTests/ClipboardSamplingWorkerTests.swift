import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class ClipboardSamplingWorkerTests: XCTestCase {
    func testPauseStopsPollingAndResumeSkipsCopiesMadeWhilePaused() throws {
        let pasteboard = CountingWorkerPasteboard()
        let notifications = NotificationCenter()
        let output = WorkerSnapshots()
        let worker = ClipboardSamplingWorker(
            sampler: ClipboardSnapshotSampler(pasteboard: pasteboard, isRecordingEnabled: true),
            notificationCenter: notifications
        )
        let queue = try workerQueue(worker)
        defer { worker.stop(); queue.sync {} }
        worker.start { output.append($0) }
        worker.updateRecordingEnabled(false)
        queue.sync {}
        let pausedReads = pasteboard.reads
        Thread.sleep(forTimeInterval: 0.36)
        queue.sync {}
        XCTAssertEqual(pasteboard.reads, pausedReads, "Paused worker must remove its 100 ms timer")
        XCTAssertEqual(pasteboard.payloadReads, 0)

        pasteboard.copy()
        worker.updateRecordingEnabled(true)
        queue.sync {}
        notifications.post(name: .macToolsPasteboardDidWrite, object: nil)
        queue.sync {}
        XCTAssertEqual(output.values.count, 0, "Copies made while paused must not be replayed")
        pasteboard.copy()
        notifications.post(name: .macToolsPasteboardDidWrite, object: nil)
        queue.sync {}
        XCTAssertEqual(output.values.map(\.changeCount), [2])
        XCTAssertEqual(pasteboard.payloadReads, 1)
    }

    func testRepeatedStartAndStopDoNotAccumulateObserversOrTimers() throws {
        let pasteboard = CountingWorkerPasteboard()
        let notifications = NotificationCenter()
        let output = WorkerSnapshots()
        let worker = ClipboardSamplingWorker(
            sampler: ClipboardSnapshotSampler(pasteboard: pasteboard, isRecordingEnabled: true),
            notificationCenter: notifications
        )
        let queue = try workerQueue(worker)
        defer { worker.stop(); queue.sync {} }
        for _ in 0..<3 {
            worker.start { output.append($0) }
            worker.start { _ in XCTFail("Repeated start must keep the existing callback") }
            worker.updateRecordingEnabled(false)
            queue.sync {}
            let beforeNotification = pasteboard.reads
            notifications.post(name: .macToolsPasteboardDidWrite, object: nil)
            queue.sync {}
            XCTAssertEqual(pasteboard.reads, beforeNotification + 1, "Exactly one observer remains")
            worker.updateRecordingEnabled(true)
            queue.sync {}
            pasteboard.copy()
            notifications.post(name: .macToolsPasteboardDidWrite, object: nil)
            queue.sync {}
            worker.stop()
            queue.sync {}
            let stoppedReads = pasteboard.reads
            notifications.post(name: .macToolsPasteboardDidWrite, object: nil)
            Thread.sleep(forTimeInterval: 0.36)
            queue.sync {}
            XCTAssertEqual(pasteboard.reads, stoppedReads, "Stop removes both timer and observer")
        }
        XCTAssertEqual(output.values.map(\.changeCount), [1, 2, 3])
        XCTAssertEqual(pasteboard.payloadReads, 3)
    }

    // Drain the production serial queue instead of guessing when asynchronous configuration finished.
    private func workerQueue(_ worker: ClipboardSamplingWorker) throws -> DispatchQueue {
        try XCTUnwrap(Mirror(reflecting: worker).children.first { $0.label == "queue" }?.value as? DispatchQueue)
    }
}

private final class CountingWorkerPasteboard: PasteboardClient, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var getterCount = 0
    private var payloadCount = 0
    var changeCount: Int { lock.withLock { getterCount += 1; return count } }
    var reads: Int { lock.withLock { getterCount } }
    var payloadReads: Int { lock.withLock { payloadCount } }
    func copy() { lock.withLock { count += 1 } }
    func readPayload() -> ClipboardPayload {
        lock.withLock { payloadCount += 1 }
        return ClipboardPayload(text: "synthetic worker test")
    }
}

private final class WorkerSnapshots: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [ClipboardSnapshot] = []
    var values: [ClipboardSnapshot] { lock.withLock { snapshots } }
    func append(_ value: ClipboardSnapshot) { lock.withLock { snapshots.append(value) } }
}
