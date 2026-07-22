import Foundation
import XCTest
@testable import MacToolsCore

final class DriveSyncCycleRunnerTests: XCTestCase {
    private enum TestError: Error {
        case unexpectedDownload
    }

    func testInitialCycleWritesReplicaAndStableRerunDoesNotAdvanceRevision() throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriveSyncCycleRunnerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        let rootURL = workingDirectory.appendingPathComponent("MacTools Sync", isDirectory: true)
        let store = DriveSyncStore(rootURL: rootURL)
        _ = try store.prepare(now: Date(timeIntervalSince1970: 100))

        let database = try MacToolsDatabase.inMemory()
        let payloadStore = PayloadStore(
            rootDirectory: workingDirectory.appendingPathComponent("Payloads", isDirectory: true)
        )
        let clipboardRepository = ClipboardRepository(
            database: database,
            payloadStore: payloadStore
        )
        let preferenceRepository = PreferenceRepository(database: database)
        try preferenceRepository.save(.defaults, enqueuesSyncChange: false)
        let deviceOverrideRepository = DeviceOverrideRepository(database: database)
        let deviceID = try deviceOverrideRepository.deviceID().uuidString
        let now = Date(timeIntervalSince1970: 200)
        let runner = DriveSyncCycleRunner(
            localRepository: SyncLocalRepository(
                database: database,
                clipboardRepository: clipboardRepository,
                preferenceRepository: preferenceRepository
            ),
            deviceOverrideRepository: deviceOverrideRepository,
            payloadStore: payloadStore,
            currentDate: { now },
            deviceName: { "Test Mac" },
            requestDownload: { _ in throw TestError.unexpectedDownload }
        )
        let configuration = DriveSyncCycleConfiguration(
            historyLimit: 500,
            clipboardScope: .allHistory,
            storageLimit: .megabytes512
        )

        let first = try runner.run(rootURL: rootURL, configuration: configuration)
        let firstReplica = try XCTUnwrap(store.replicas(generation: 1).first)
        let second = try runner.run(rootURL: rootURL, configuration: configuration)
        let secondReplica = try XCTUnwrap(store.replicas(generation: 1).first)

        XCTAssertEqual(firstReplica.manifest.deviceID, deviceID)
        XCTAssertEqual(firstReplica.manifest.deviceName, "Test Mac")
        XCTAssertEqual(firstReplica.manifest.revision, 1)
        XCTAssertEqual(secondReplica.manifest, firstReplica.manifest)
        XCTAssertNil(first.remoteSettings)
        XCTAssertNil(second.remoteSettings)
        XCTAssertEqual(first.devices, second.devices)
        XCTAssertEqual(first.devices.map(\.id), [deviceID])
        guard case let .synced(lastSyncAt, usage) = second.status else {
            return XCTFail("Expected a synced status")
        }
        XCTAssertEqual(lastSyncAt, now)
        XCTAssertEqual(usage.ordinaryHistoryCount, 0)
    }
}
