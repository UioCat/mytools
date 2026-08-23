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
        let descriptor = try store.prepare(now: Date(timeIntervalSince1970: 100))

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
        let localRepository = SyncLocalRepository(
            database: database,
            clipboardRepository: clipboardRepository,
            preferenceRepository: preferenceRepository
        )
        let runner = DriveSyncCycleRunner(
            localRepository: localRepository,
            deviceOverrideRepository: deviceOverrideRepository,
            payloadStore: payloadStore,
            currentDate: { now },
            deviceName: { "Test Mac" },
            requestDownload: { _ in throw TestError.unexpectedDownload },
            makeStore: {
                DriveSyncStore(
                    rootURL: $0,
                    publicationLedger: localRepository.snapshotPublicationLedger
                )
            }
        )
        let configuration = DriveSyncCycleConfiguration(
            historyLimit: 500,
            clipboardScope: .allHistory,
            storageLimit: .megabytes512
        )

        let first = try runner.run(rootURL: rootURL, configuration: configuration)
        let firstReplica = try XCTUnwrap(store.replicas(generation: 1).first)
        try Data(repeating: 7, count: 1_024).write(
            to: rootURL.appendingPathComponent("inventory-probe.bin")
        )
        let second = try runner.run(rootURL: rootURL, configuration: configuration)
        let secondReplica = try XCTUnwrap(store.replicas(generation: 1).first)

        XCTAssertEqual(firstReplica.manifest.deviceID, deviceID)
        XCTAssertEqual(firstReplica.manifest.deviceName, "Test Mac")
        XCTAssertEqual(firstReplica.manifest.revision, 1)
        let publicationIdentity = SyncSnapshotPublicationIdentity(
            storeID: descriptor.storeID,
            deviceID: deviceID,
            generation: 1,
            revision: 1,
            snapshotDirectory: try XCTUnwrap(firstReplica.manifest.snapshotDirectory)
        )
        XCTAssertEqual(
            try localRepository.snapshotPublicationLedger.record(for: publicationIdentity)?.state,
            .published
        )
        XCTAssertEqual(secondReplica.manifest, firstReplica.manifest)
        XCTAssertNil(first.remoteSettings)
        XCTAssertNil(second.remoteSettings)
        XCTAssertEqual(first.devices, second.devices)
        XCTAssertEqual(first.devices.map(\.id), [deviceID])
        guard case let .synced(_, firstUsage) = first.status else {
            return XCTFail("Expected the initial cycle to sync")
        }
        guard case let .synced(lastSyncAt, usage) = second.status else {
            return XCTFail("Expected a synced status")
        }
        XCTAssertEqual(lastSyncAt, now)
        XCTAssertEqual(usage.ordinaryHistoryCount, 0)
        XCTAssertEqual(usage, firstUsage)

        runner.invalidateObservationCache()
        let audited = try runner.run(rootURL: rootURL, configuration: configuration)
        guard case let .synced(_, auditedUsage) = audited.status else {
            return XCTFail("Expected the audited cycle to sync")
        }
        XCTAssertEqual(auditedUsage.metadataBytes, firstUsage.metadataBytes + 1_024)
    }

    func testStableRerunDoesNotMaterializeAlreadyUploadedLocalImage() throws {
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
        let imageData = Self.pngData()
        let imageID = UUID()
        try clipboardRepository.upsertPNG(
            ClipboardItem(
                id: imageID,
                kind: .imageData,
                displayTitle: "stable image",
                searchableText: "stable image",
                text: nil,
                originalPath: nil,
                cachedFilePath: nil,
                thumbnailPath: nil,
                sourceApp: "Tests",
                contentHash: ClipboardContentHasher.sha256String(for: imageData),
                createdAt: Date(timeIntervalSince1970: 150),
                lastUsedAt: nil,
                useCount: 0,
                isPinned: false,
                isFavorite: false
            ),
            data: imageData
        )
        let preferenceRepository = PreferenceRepository(database: database)
        try preferenceRepository.save(.defaults, enqueuesSyncChange: false)
        let deviceOverrideRepository = DeviceOverrideRepository(database: database)
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
        let cachedFilePath = try XCTUnwrap(
            try clipboardRepository.item(id: imageID)?.cachedFilePath
        )
        try Data(repeating: 0, count: imageData.count).write(
            to: URL(fileURLWithPath: cachedFilePath),
            options: .atomic
        )

        let second = try runner.run(rootURL: rootURL, configuration: configuration)
        let secondReplica = try XCTUnwrap(store.replicas(generation: 1).first)

        guard case .synced = first.status else {
            return XCTFail("Expected the initial cycle to sync")
        }
        guard case .synced = second.status else {
            return XCTFail("Stable cycle unexpectedly read or validated local image bytes")
        }
        XCTAssertEqual(secondReplica.manifest, firstReplica.manifest)
    }

    private static func pngData() -> Data {
        Data(base64Encoded: onePixelPNGBase64)!
    }

    private static let onePixelPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
