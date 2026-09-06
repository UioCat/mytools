import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class ICloudSyncSchedulingTests: XCTestCase {
    func testManualSyncDoesNotCancelQueuedReset() throws {
        let fixture = try makeFixture()
        defer { fixture.coordinator.setEnabled(false) }
        fixture.coordinator.setEnabled(true)
        wait(for: [fixture.scheduler.scheduled], timeout: 3)
        let blocked = expectation(description: "coordinator queue paused")
        let resume = fixture.scheduler.pauseQueue(onPaused: { blocked.fulfill() })
        defer { resume.signal() }
        wait(for: [blocked], timeout: 3)

        fixture.coordinator.resetSyncData()
        fixture.coordinator.syncNow()
        fixture.scheduler.scheduled = expectation(description: "reset and sync completed")
        resume.signal()
        wait(for: [fixture.scheduler.scheduled], timeout: 3)

        let store = DriveSyncStore(rootURL: fixture.root)
        let storeID = try store.readProtocol().storeID
        XCTAssertEqual(try store.highestResetGeneration(), 2)
        XCTAssertEqual(try fixture.repository.currentGeneration(storeID: storeID), 2)
    }

    func testManualSyncInvalidatesPreviouslyScheduledTimers() throws {
        let fixture = try makeFixture()
        defer { fixture.coordinator.setEnabled(false) }
        for index in 0..<4 {
            if index > 0 { fixture.scheduler.scheduled = expectation(description: "manual cycle \(index)") }
            if index == 0 { fixture.coordinator.setEnabled(true) } else { fixture.coordinator.syncNow() }
            wait(for: [fixture.scheduler.scheduled], timeout: 3)
        }
        XCTAssertEqual(fixture.scheduler.pendingCount, 4)
        let before = fixture.scheduler.scheduleCount
        for _ in 0..<4 {
            let drained = expectation(description: "timer drained")
            fixture.scheduler.fire(onIdle: { drained.fulfill() })
            wait(for: [drained], timeout: 3)
        }
        XCTAssertEqual(fixture.scheduler.scheduleCount, before + 1, "Only the newest timer may start another cycle")
        XCTAssertEqual(fixture.scheduler.pendingCount, 1)
    }

    func testUnchangedRemoteConfigurationDoesNotCancelNextPeriodicSync() throws {
        let fixture = try makeFixture()
        defer { fixture.coordinator.setEnabled(false) }
        fixture.coordinator.setEnabled(true)
        wait(for: [fixture.scheduler.scheduled], timeout: 3)
        fixture.scheduler.scheduled = expectation(description: "next periodic cycle scheduled")
        fixture.coordinator.updateConfiguration(historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes512)
        fixture.scheduler.fire()
        wait(for: [fixture.scheduler.scheduled], timeout: 3)
    }

    func testChangedRemoteConfigurationRestartsSyncWhenPreviousCycleIsIdle() throws {
        let fixture = try makeFixture()
        defer { fixture.coordinator.setEnabled(false) }
        fixture.coordinator.setEnabled(true)
        wait(for: [fixture.scheduler.scheduled], timeout: 3)
        fixture.scheduler.scheduled = expectation(description: "changed configuration scheduled")
        fixture.coordinator.updateConfiguration(historyLimit: 500, clipboardScope: .allHistory, storageLimit: .gigabyte1)
        fixture.scheduler.fire()
        wait(for: [fixture.scheduler.scheduled], timeout: 3)
    }

    private func makeFixture() throws -> (
        coordinator: ICloudDriveSyncCoordinator, scheduler: ManualSyncScheduler,
        root: URL, repository: SyncLocalRepository
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncScheduling-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("cloud")
        _ = try DriveSyncStore(rootURL: root).prepare()
        let database = try MacToolsDatabase.inMemory()
        let payloads = PayloadStore(rootDirectory: directory.appendingPathComponent("payloads"))
        let preferences = PreferenceRepository(database: database)
        try preferences.save(.defaults, enqueuesSyncChange: false)
        let repository = SyncLocalRepository(
            database: database, clipboardRepository: ClipboardRepository(database: database, payloadStore: payloads),
            preferenceRepository: preferences
        )
        let scheduler = ManualSyncScheduler(scheduled: expectation(description: "initial periodic schedule"))
        let coordinator = ICloudDriveSyncCoordinator(
            localRepository: repository, deviceOverrideRepository: DeviceOverrideRepository(database: database),
            payloadStore: payloads,
            encryptedCredentialStore: EncryptedCredentialStore(
                envelopeURL: directory.appendingPathComponent("credential.json"),
                migrationMarkerURL: directory.appendingPathComponent("migration.json")
            ),
            historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes512, rootURL: root,
            statusHandler: { _ in }, remoteSettingsHandler: { _ in }, devicesHandler: { _ in }, credentialStateHandler: { _ in },
            periodicScheduler: { queue, work in scheduler.schedule(queue: queue, work: work) }
        )
        return (coordinator, scheduler, root, repository)
    }
}

private final class ManualSyncScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var notification: XCTestExpectation
    private var didNotify = false
    private var pending: [(DispatchQueue, @Sendable () -> Void)] = []
    private var count = 0
    var pendingCount: Int { lock.withLock { pending.count } }
    var scheduleCount: Int { lock.withLock { count } }
    var scheduled: XCTestExpectation {
        get { lock.withLock { notification } }
        set { lock.withLock { notification = newValue; didNotify = false } }
    }

    init(scheduled: XCTestExpectation) { notification = scheduled }

    func schedule(queue: DispatchQueue, work: @escaping @Sendable () -> Void) {
        let notification = lock.withLock { () -> XCTestExpectation? in
            pending.append((queue, work))
            count += 1
            guard !didNotify else { return nil }
            didNotify = true
            return self.notification
        }
        notification?.fulfill()
    }

    func fire(onIdle: @escaping @Sendable () -> Void = {}) {
        let work = lock.withLock {
            pending.isEmpty ? nil : pending.removeFirst()
        }
        if let (queue, work) = work {
            queue.async {
                work()
                queue.async(execute: onIdle)
            }
        } else { onIdle() }
    }

    func pauseQueue(onPaused: @escaping @Sendable () -> Void) -> DispatchSemaphore {
        let resume = DispatchSemaphore(value: 0)
        let queue = lock.withLock { pending.first!.0 }
        queue.async {
            onPaused()
            resume.wait()
        }
        return resume
    }
}
