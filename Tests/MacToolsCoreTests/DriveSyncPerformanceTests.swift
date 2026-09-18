import Foundation
import XCTest
@testable import MacToolsCore

final class DriveSyncPerformanceTests: XCTestCase {
    func testOutOfScopeCopyDoesNotPublishOrLoseFutureScopeExpansion() throws {
        let fixture = try makeFixture()
        let configuration = DriveSyncCycleConfiguration(
            historyLimit: 500, clipboardScope: .favoritesAndPinned, storageLimit: .megabytes512
        )
        _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        let before = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        try fixture.capture("ordinary synthetic copy")

        for _ in 0..<3 {
            _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        }
        let after = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        XCTAssertEqual(after.manifest, before.manifest)
        XCTAssertTrue(after.clipboard.records.isEmpty)

        _ = try fixture.runner.run(rootURL: fixture.root, configuration: .init(
            historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes512
        ))
        XCTAssertEqual(try fixture.store.replicas(generation: 1).first?.clipboard.records.count, 1)
    }

    func testPeerConflictDoesNotDiscardHealthyInventoryEveryCycle() throws {
        let fixture = try makeFixture()
        let peer = try PerformanceSyncFixture(root: fixture.root)
        let configuration = DriveSyncCycleConfiguration(
            historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes512
        )
        _ = try peer.runner.run(rootURL: fixture.root, configuration: configuration)
        _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        fixture.files.conflictingDevice = try peer.overrides.deviceID().uuidString
        _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        let scans = fixture.files.inventoryScans

        for _ in 0..<3 {
            let result = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
            XCTAssertEqual(result.status, .conflictNeedsAttention)
        }
        XCTAssertEqual(fixture.files.inventoryScans, scans)

        fixture.files.conflictingDevice = nil
        let recovered = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        guard case .synced = recovered.status else { return XCTFail("Conflict recovery was hidden by the cache") }
    }

    func testIdleCyclesDrainBoundedPreparedBacklogWithoutPublishing() throws {
        let fixture = try makeFixture()
        let configuration = DriveSyncCycleConfiguration(
            historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes512
        )
        _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        let replica = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        let descriptor = try fixture.store.readProtocol()
        let revisions = fixture.root.appendingPathComponent("replicas/\(replica.manifest.deviceID)/revisions")
        let untracked = revisions.appendingPathComponent("legacy-untracked")
        try FileManager.default.createDirectory(at: untracked, withIntermediateDirectories: true)
        var candidates: [URL] = []
        for index in 0..<40 {
            let name = "prepared-\(index)"
            let directory = revisions.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 128).write(to: directory.appendingPathComponent("clipboard.json"))
            candidates.append(directory)
            try fixture.local.snapshotPublicationLedger.recordPrepared(.init(
                storeID: descriptor.storeID, deviceID: replica.manifest.deviceID,
                generation: 1, revision: Int64(index + 2), snapshotDirectory: name,
                snapshotDigests: .init(clipboard: "synthetic", preferences: "synthetic", tombstones: "synthetic"),
                manifestDigest: "synthetic", state: .prepared, supersededByRevision: nil, updatedAt: Date()
            ))
        }
        _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
        let remaining = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }.count
        XCTAssertGreaterThanOrEqual(remaining, 24)
        XCTAssertLessThan(remaining, 40)
        for _ in 0..<40 {
            _ = try fixture.runner.run(rootURL: fixture.root, configuration: configuration)
            if candidates.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) { break }
        }
        XCTAssertTrue(candidates.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: untracked.path))
        XCTAssertEqual(try fixture.store.replicas(generation: 1).first?.manifest, replica.manifest)
    }

    func testIndexedInventoryTracksAddedReplacedAndRemovedRevisions() throws {
        let fixture = try makeFixture()
        let revisions = fixture.root.appendingPathComponent("replicas/synthetic/revisions")
        let directory = revisions.appendingPathComponent("revision-a")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("clipboard.json")
        try Data(repeating: 1, count: 100).write(to: file)
        let cache = SyncRevisionInventoryCache()
        XCTAssertEqual(try fixture.store.storageInventory(revisionCache: cache), try fixture.store.storageInventory())
        XCTAssertEqual(try fixture.store.storageInventory(revisionCache: cache), try fixture.store.storageInventory())

        try Data(repeating: 2, count: 250).write(to: file, options: .atomic)
        let second = revisions.appendingPathComponent("revision-b")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 70).write(to: second.appendingPathComponent("preferences.json"))
        XCTAssertEqual(try fixture.store.storageInventory(revisionCache: cache), try fixture.store.storageInventory())
        try FileManager.default.removeItem(at: directory)
        XCTAssertEqual(try fixture.store.storageInventory(revisionCache: cache), try fixture.store.storageInventory())
        XCTAssertThrowsError(try fixture.store.storageInventory(
            revisionCache: cache, cancellation: .init(isCancelled: { true })
        )) { XCTAssertEqual($0 as? SyncCycleCancellationError, .cancelled) }
    }

    func testRevisionIndexReusesMeasurementsAndExpiresForInPlaceRepairs() throws {
        let fixture = try makeFixture()
        let values = try fixture.root.resourceValues(forKeys: [
            .contentModificationDateKey, .creationDateKey, .fileResourceIdentifierKey
        ])
        let cache = SyncRevisionInventoryCache()
        let now = Date(timeIntervalSince1970: 1_000)
        var measurements = 0
        func measure() -> Int64 { measurements += 1; return Int64(measurements) }
        XCTAssertEqual(cache.bytes(at: fixture.root, values: values, now: now, measure: measure), 1)
        XCTAssertEqual(cache.bytes(at: fixture.root, values: values, now: now.addingTimeInterval(300), measure: measure), 1)
        XCTAssertEqual(measurements, 1)
        XCTAssertEqual(cache.bytes(at: fixture.root, values: values, now: now.addingTimeInterval(1_800), measure: measure), 2)
        cache.retain([])
        XCTAssertEqual(cache.bytes(at: fixture.root, values: values, now: now.addingTimeInterval(1_801), measure: measure), 3)
    }

    private func makeFixture() throws -> PerformanceSyncFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncPerformance-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return try PerformanceSyncFixture(root: directory)
    }
}

private final class PerformanceSyncFixture: @unchecked Sendable {
    let root: URL
    let clipboard: ClipboardRepository
    let overrides: DeviceOverrideRepository
    let local: SyncLocalRepository
    let files = PerformanceSyncFiles()
    let store: DriveSyncStore
    let runner: DriveSyncCycleRunner

    init(root: URL) throws {
        self.root = root
        store = DriveSyncStore(rootURL: root)
        _ = try store.prepare()
        let database = try MacToolsDatabase.inMemory()
        let payloads = PayloadStore(rootDirectory: root.appendingPathComponent(".test-payloads-\(UUID().uuidString)"))
        clipboard = ClipboardRepository(database: database, payloadStore: payloads)
        let preferences = PreferenceRepository(database: database)
        try preferences.save(.defaults, enqueuesSyncChange: false)
        overrides = DeviceOverrideRepository(database: database)
        local = SyncLocalRepository(database: database, clipboardRepository: clipboard, preferenceRepository: preferences)
        let files = files
        let ledger = local.snapshotPublicationLedger
        runner = DriveSyncCycleRunner(
            localRepository: local, deviceOverrideRepository: overrides, payloadStore: payloads,
            deviceName: { "Synthetic Mac" }, requestDownload: { _ in },
            makeStore: { DriveSyncStore(rootURL: $0, fileCoordinator: files, publicationLedger: ledger, onInventoryScan: { files.recordInventoryScan() }) }
        )
    }

    func capture(_ text: String) throws {
        _ = try clipboard.upsert(ClipboardItem(
            id: UUID(), kind: .text, displayTitle: text, searchableText: text, text: text,
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: "Tests",
            contentHash: ClipboardContentHasher.sha256String(for: Data("text:\(text)".utf8)),
            createdAt: Date(), lastUsedAt: nil, useCount: 0, isPinned: false, isFavorite: false
        ))
    }
}

private final class PerformanceSyncFiles: SyncFileCoordinating, @unchecked Sendable {
    private let stateLock = NSLock()
    private var conflict: String?
    private var scans = 0
    var conflictingDevice: String? {
        get { stateLock.withLock { conflict } }
        set { stateLock.withLock { conflict = newValue } }
    }
    var inventoryScans: Int { stateLock.withLock { scans } }

    func recordInventoryScan() {
        stateLock.withLock { scans += 1 }
    }

    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        try DirectSyncFileCoordinator().readData(at: url, options: options)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try DirectSyncFileCoordinator().writeData(data, to: url)
    }

    func coordinateManifest(
        at url: URL, deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation
    ) throws -> SyncManifestMutationResult {
        if url.deletingLastPathComponent().lastPathComponent == conflictingDevice {
            throw DriveSyncStoreError.fileConflict(url)
        }
        return try DirectSyncFileCoordinator().coordinateManifest(at: url, deciding: mutation)
    }
}
