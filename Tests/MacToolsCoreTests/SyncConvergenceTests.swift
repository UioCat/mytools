import Foundation
import XCTest
@testable import MacToolsCore

/// 两台设备各自使用真实 SQLite、载荷目录和生产 runner；传输按文件可延迟、乱序、重放。
final class SyncConvergenceTests: XCTestCase {
    func testIncompleteOwnRecoveryNeverReplacesOnlyCloudCopy() throws {
        for corrupt in [false, true] {
            let network = try SyncTestNetwork()
            defer { network.remove() }
            let id = try network.a.capture("fixture-only-cloud-copy")
            try network.a.run()
            let delivery = try network.a.delivery()
            let objectPath = try XCTUnwrap(delivery.keys.first { $0.hasPrefix("objects/") })
            try network.a.clipboard.delete(id: id, createsTombstone: false)
            try network.a.overrides.setReplicaRevision(0)
            if corrupt {
                try network.a.receive([objectPath: Data("invalid-fixture".utf8)])
            } else {
                try FileManager.default.removeItem(at: network.a.root.appendingPathComponent(objectPath))
            }
            try network.restart()
            let manifestPath = "replicas/\(network.a.id)/manifest.json"
            let originalManifest = try XCTUnwrap(delivery[manifestPath])
            for _ in 0..<2 {
                let status = try network.a.run().status
                XCTAssertEqual(status, corrupt ? .failed : .waitingForDownload)
                XCTAssertEqual(try network.a.delivery()[manifestPath], originalManifest)
                XCTAssertEqual(try network.a.overrides.replicaRevision(), 0)
            }
            try network.restart()
            try network.a.receive([objectPath: try XCTUnwrap(delivery[objectPath])])
            try network.exchange(rounds: 4)
            XCTAssertEqual(try network.a.texts(), ["fixture-only-cloud-copy"])
            XCTAssertEqual(try network.b.texts(), ["fixture-only-cloud-copy"])
        }
    }

    func testConcurrentDeletesKeepCloudEvidenceForFreshDeviceWithStaleSnapshot() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        let id = try network.a.capture("fixture-double-delete")
        try network.exchange(rounds: 4)
        let stale = try network.a.delivery()
        try network.a.clipboard.delete(id: id)
        try network.b.clipboard.delete(id: id)
        try network.a.run()
        try network.b.run()
        let fromA = try network.a.delivery()
        let fromB = try network.b.delivery()
        try network.a.receive(fromB)
        try network.b.receive(fromA)
        try network.a.run()
        try network.b.run()
        try network.exchange(rounds: 4)
        let tombstones = try network.a.store.replicas(generation: 1).flatMap(\.tombstones.records)
        XCTAssertTrue(tombstones.contains { $0.targetRecordName == id.uuidString })
        let fresh = try SyncTestDevice(directory: network.directory.appendingPathComponent("fresh"))
        try fresh.receive(["protocol.json": Data(contentsOf: network.a.root.appendingPathComponent("protocol.json"))])
        _ = try fresh.store.prepare()
        try fresh.receive(stale)
        try fresh.receive(network.b.delivery())
        try fresh.run()
        XCTAssertEqual(try fresh.texts(), [])
    }

    func testDifferentCaptureDatesConvergeOnEarliestCreationAndLatestMetadata() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-dates", source: "Earlier", at: Date(timeIntervalSince1970: 100))
        try network.b.capture("fixture-dates", source: "Later", at: Date(timeIntervalSince1970: 200))
        try network.exchange(rounds: 5)
        for device in [network.a, network.b] {
            let item = try XCTUnwrap(device.clipboard.search("", limit: 10).first)
            XCTAssertEqual(item.createdAt, Date(timeIntervalSince1970: 100))
            XCTAssertEqual(item.lastCapturedAt, Date(timeIntervalSince1970: 200))
            XCTAssertEqual(item.sourceApp, "Later")
        }
        let before = try network.revisions()
        try network.exchange(rounds: 3)
        XCTAssertEqual(try network.revisions(), before)
    }

    func testAppliedSettingsAreRedeliveredAfterLaterPublicationFailure() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.exchange(rounds: 3)
        var settings = try XCTUnwrap(network.a.preferences.load())
        settings.clipboard.isRecordingEnabled = false
        try network.a.preferences.save(settings)
        try network.a.run()
        try network.b.receive(network.a.delivery())
        network.b.files.failure = .beforePublication
        XCTAssertThrowsError(try network.b.run())
        XCTAssertEqual(try network.b.preferences.load()?.clipboard.isRecordingEnabled, false)
        let retried = try network.b.run()
        XCTAssertEqual(retried.remoteSettings?.clipboard.isRecordingEnabled, false)
    }

    func testRemovingPeerDoesNotRegressPublishedVersionVector() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-a")
        try network.b.capture("fixture-b")
        try network.exchange(rounds: 4)
        let before = try XCTUnwrap(network.a.store.replicas(generation: 1).first { $0.manifest.deviceID == network.a.id })
        try network.a.store.writeRemovedDevice(SyncRemovedDeviceMarker(
            removedDeviceID: network.b.id, removerDeviceID: network.a.id, generation: 1, removedAt: Date()
        ))
        try network.a.run(forceWrite: true)
        let after = try XCTUnwrap(network.a.store.replicas(generation: 1).first { $0.manifest.deviceID == network.a.id })
        XCTAssertGreaterThan(after.manifest.revision, before.manifest.revision)
        XCTAssertGreaterThanOrEqual(after.manifest.seenRevisions[network.b.id] ?? 0, before.manifest.seenRevisions[network.b.id] ?? 0)
    }

    func testNewerOwnManifestArrivingDuringPublicationIsImportedBeforeProgressAdvances() throws {
        for arrival in [2, 3] {
            let network = try SyncTestNetwork()
            defer { network.remove() }
            try network.a.capture("fixture-initial")
            try network.a.run()
            let path = "replicas/\(network.a.id)/manifest.json"
            let initial = try XCTUnwrap(network.a.delivery()[path])
            let cloudID = try network.a.capture("fixture-cloud")
            let remote = try network.a.sync.exportBundle(deviceID: network.a.id, generation: 1, revision: 3, scope: .allHistory)
            _ = try network.a.store.write(remote, seenRevisions: [:], updatedAt: Date())
            let newer = try XCTUnwrap(network.a.delivery()[path])
            try network.a.clipboard.delete(id: cloudID, createsTombstone: false)
            try network.a.receive([path: initial])
            try network.a.capture("fixture-local")
            network.a.files.onManifestAccess = { url, count in
                if count == arrival { try newer.write(to: url, options: .atomic) }
            }
            XCTAssertThrowsError(try network.a.run()) { error in
                XCTAssertEqual(error as? DriveSyncCycleRetryError, .newerRemoteReplica)
            }
            XCTAssertEqual(try network.a.overrides.replicaRevision(), 1)
            XCTAssertTrue(try network.a.sync.hasPendingChanges())
            network.a.files.onManifestAccess = nil
            try network.exchange(rounds: 5)
            XCTAssertEqual(try network.b.texts(), ["fixture-cloud", "fixture-initial", "fixture-local"])
        }
    }

    func testSeededOfflineDuplicateAndReorderedSchedulesConverge() throws {
        for seed in 1...12 {
            let network = try SyncTestNetwork()
            defer { network.remove() }
            var state = UInt64(seed)
            var pending: [(Bool, [String: Data])] = []
            var expected = Set<String>()
            for step in 0..<24 {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                let fromA = state & 4 == 0
                let device = fromA ? network.a : network.b
                let text = "fixture-seed-\(seed)-\(step % 7)"
                expected.insert(text)
                try device.capture(text, source: fromA ? "Fixture A" : "Fixture B")
                if let item = try device.clipboard.search("", limit: 100).first {
                    if step % 3 == 0 { try device.clipboard.setFavorite(id: item.id, isFavorite: true) }
                    if step % 4 == 0 { try device.clipboard.setPinned(id: item.id, isPinned: true) }
                }
                try device.run()
                pending.append((fromA, try device.delivery()))
                if state & 8 != 0 {
                    let index = Int(state % UInt64(pending.count))
                    let (sourceIsA, files) = pending.remove(at: index)
                    try (sourceIsA ? network.b : network.a).receive(files)
                }
                if step == 12 { try network.restart() }
            }
            for (sourceIsA, files) in pending.reversed() {
                try (sourceIsA ? network.b : network.a).receive(files)
            }
            try network.exchange(rounds: 6)
            XCTAssertEqual(try network.a.texts(), expected.sorted(), "seed \(seed)")
            XCTAssertEqual(try network.b.texts(), expected.sorted(), "seed \(seed)")
            let itemsA = try network.a.clipboard.search("", limit: 100).sorted { $0.id.uuidString < $1.id.uuidString }
            let itemsB = try network.b.clipboard.search("", limit: 100).sorted { $0.id.uuidString < $1.id.uuidString }
            XCTAssertEqual(itemsA.map(\.id), itemsB.map(\.id), "seed \(seed)")
            XCTAssertEqual(itemsA.map(\.isFavorite), itemsB.map(\.isFavorite), "seed \(seed)")
            XCTAssertEqual(itemsA.map(\.isPinned), itemsB.map(\.isPinned), "seed \(seed)")
            let stable = try network.revisions()
            try network.exchange(rounds: 4)
            XCTAssertEqual(try network.revisions(), stable, "seed \(seed)")
        }
    }

    func testImagePayloadArrivesLateAndSurvivesRestartByteForByte() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let id = UUID()
        try network.a.clipboard.upsertPNG(ClipboardItem(
            id: id, kind: .imageData, displayTitle: "Fixture PNG", searchableText: "Fixture PNG", text: nil,
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: "Fixture",
            contentHash: ClipboardContentHasher.sha256String(for: png), createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil, useCount: 0, isPinned: false, isFavorite: false
        ), data: png)
        try network.a.run()
        let delivery = try network.a.delivery()
        try network.b.receive(delivery.filter { !$0.key.hasSuffix(".png") })
        XCTAssertEqual(try network.b.run().status, .waitingForDownload)
        try network.restart()
        try network.b.receive(delivery)
        try network.exchange(rounds: 4)
        let path = try XCTUnwrap(network.b.clipboard.item(id: id)?.cachedFilePath)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), png)
        let stable = try network.revisions()
        try network.exchange(rounds: 3)
        XCTAssertEqual(try network.revisions(), stable)
    }

    func testLocalChangeDuringPublicationRemainsPendingAndIsPublishedNextCycle() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.run()
        try network.a.capture("fixture-before")
        network.a.files.beforePublication = { try network.a.capture("fixture-during") }
        try network.a.run()
        XCTAssertTrue(try network.a.sync.hasPendingChanges())
        try network.exchange(rounds: 4)
        XCTAssertEqual(try network.b.texts(), ["fixture-before", "fixture-during"])
    }

    func testCorruptPeerContentDoesNotBlockHealthyPeerAndRecoversAfterRepair() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-corrupt")
        try network.a.run()
        let healthy = try network.a.delivery()
        var corrupt = healthy
        for path in corrupt.keys where path.hasPrefix("objects/") { corrupt[path] = Data("invalid-fixture".utf8) }
        try network.b.receive(corrupt)
        XCTAssertEqual(try network.b.run().status, .failed)
        XCTAssertTrue(try network.b.sync.receipts().isEmpty)
        try network.b.capture("fixture-healthy")
        try network.b.run()
        try network.a.receive(network.b.delivery().filter { !$0.key.hasPrefix("objects/") || healthy[$0.key] == nil })
        try network.a.run()
        XCTAssertEqual(try network.a.texts(), ["fixture-corrupt", "fixture-healthy"])
        try network.b.receive(healthy)
        try network.exchange(rounds: 4)
        XCTAssertEqual(try network.b.texts(), ["fixture-corrupt", "fixture-healthy"])
    }

    func testSimultaneousDuplicateCaptureWithDifferentMetadataConvergesWithoutChurn() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-duplicate", source: "Fixture A")
        try network.b.capture("fixture-duplicate", source: "Fixture B")
        // 两端先独立发布，随后交换同一批旧观察，模拟真正的同时复制。
        try network.a.run()
        try network.b.run()
        for _ in 0..<8 {
            let fromA = try network.a.delivery()
            let fromB = try network.b.delivery()
            try network.a.receive(fromB)
            try network.b.receive(fromA)
            try network.a.run()
            try network.b.run()
        }
        let itemA = try XCTUnwrap(network.a.clipboard.search("", limit: 10).first)
        let itemB = try XCTUnwrap(network.b.clipboard.search("", limit: 10).first)
        XCTAssertEqual(itemA.id, itemB.id)
        XCTAssertEqual(itemA.sourceApp, itemB.sourceApp)
        let before = try network.revisions()
        try network.exchange(rounds: 5)
        XCTAssertEqual(try network.revisions(), before)
    }

    func testSnapshotReclamationIsReflectedInReportedCapacity() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        for index in 0..<8 {
            try network.a.capture("fixture-capacity-\(index)")
            let result = try network.a.run()
            guard case let .synced(_, usage) = result.status else { return XCTFail("Expected synced") }
            let actual = try network.a.store.storageInventory()
            XCTAssertEqual(usage.metadataBytes, actual.metadataBytes)
        }
    }

    func testOwnerRecoversReclaimedAncestorPointerAfterRestart() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-first")
        try network.a.run()
        let old = try network.a.delivery().filter { $0.key.hasSuffix("manifest.json") }
        try network.a.capture("fixture-second")
        try network.a.run()
        try network.a.receive(old)
        try network.restart()
        try network.exchange(rounds: 4)
        XCTAssertEqual(try network.b.texts(), ["fixture-first", "fixture-second"])
    }

    func testNewerOwnCloudSnapshotRestoresLocalDataBeforePublishing() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        let id = try network.a.capture("fixture-restored")
        try network.a.run()
        try network.a.clipboard.delete(id: id, createsTombstone: false)
        try network.a.overrides.setReplicaRevision(0)
        try network.a.run()
        XCTAssertEqual(try network.a.texts(), ["fixture-restored"])
    }

    func testPublicationFailureBeforeAndAfterPointerWriteRecoversAfterRestart() throws {
        for stage in [SyncTestFileCoordinator.Failure.beforePublication, .afterPublication] {
            let network = try SyncTestNetwork()
            defer { network.remove() }
            try network.a.run()
            try network.a.capture("fixture-interrupted")
            network.a.files.failure = stage
            XCTAssertThrowsError(try network.a.run())
            XCTAssertTrue(try network.a.sync.hasPendingChanges())
            try network.restart()
            try network.exchange(rounds: 5)
            XCTAssertEqual(try network.b.texts(), ["fixture-interrupted"])
            XCTAssertFalse(try network.a.sync.hasPendingChanges())
            let stable = try network.revisions()
            try network.exchange(rounds: 3)
            XCTAssertEqual(try network.revisions(), stable)
        }
    }

    func testPendingOwnSnapshotIsDownloadWaitAndDoesNotCreateMoreRevisions() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.run()
        try network.a.capture("fixture-wait")
        network.a.files.unavailableFileName = "clipboard.json"
        network.a.runner.invalidateObservationCache()
        let before = try network.a.delivery().keys.filter { $0.contains("/revisions/") }.sorted()
        for _ in 0..<3 {
            XCTAssertThrowsError(try network.a.run()) { error in
                guard case .itemNotDownloaded = error as? DriveSyncStoreError else {
                    return XCTFail("Download wait was incorrectly converted to conflict: \(error)")
                }
            }
        }
        XCTAssertEqual(try network.a.delivery().keys.filter { $0.contains("/revisions/") }.sorted(), before)
        network.a.files.unavailableFileName = nil
        try network.exchange(rounds: 4)
        XCTAssertEqual(try network.b.texts(), ["fixture-wait"])
    }

    func testTwoIdleDevicesStopPublishingAcknowledgementsAfterConvergence() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-alpha")
        try network.b.capture("fixture-beta")
        try network.exchange(rounds: 6)
        XCTAssertEqual(try network.a.texts(), ["fixture-alpha", "fixture-beta"])
        XCTAssertEqual(try network.a.texts(), try network.b.texts())
        let before = try network.revisions()
        try network.exchange(rounds: 12)
        XCTAssertEqual(try network.revisions(), before, "Stable peers must not acknowledge acknowledgements forever")
    }

    func testDelayedObjectBecomesVisibleWithoutWaitingForInventoryAudit() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-delayed")
        try network.a.run()
        let delivery = try network.a.delivery()
        try network.b.receive(delivery.filter { !$0.key.hasPrefix("objects/") })
        let waiting = try network.b.run()
        XCTAssertEqual(waiting.status, .waitingForDownload)
        XCTAssertTrue(try network.b.sync.receipts().isEmpty)
        try network.b.receive(delivery.filter { $0.key.hasPrefix("objects/") })
        let recovered = try network.b.run()
        XCTAssertEqual(try network.b.texts(), ["fixture-delayed"])
        guard case .synced = recovered.status else { return XCTFail("Late content must recover on the next cycle") }
    }

    func testManifestArrivingBeforeSnapshotsRequestsDownloadAndRecovers() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.a.capture("fixture-snapshot")
        try network.a.run()
        let delivery = try network.a.delivery()
        try network.b.receive(delivery.filter { $0.key.hasSuffix("manifest.json") })
        XCTAssertEqual(try network.b.run().status, .waitingForDownload)
        XCTAssertTrue(try network.b.sync.receipts().isEmpty)
        try network.b.receive(delivery)
        try network.b.run()
        XCTAssertEqual(try network.b.texts(), ["fixture-snapshot"])
    }

    func testOfflinePeerCannotResurrectDeletionAfterSourceRunsAlone() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        let id = try network.a.capture("fixture-deleted")
        try network.exchange(rounds: 4)
        let stale = try network.b.delivery()
        // 源设备短暂看不到另一设备目录，模拟 File Provider 目录发现延迟。
        try FileManager.default.removeItem(at: network.a.root.appendingPathComponent("replicas/\(network.b.id)"))
        try network.a.clipboard.delete(id: id)
        for _ in 0..<4 { try network.a.run() }
        try network.a.receive(stale)
        try network.exchange(rounds: 5)
        XCTAssertEqual(try network.a.texts(), [])
        XCTAssertEqual(try network.b.texts(), [])
    }

    func testConcurrentFavoriteTagsAndSettingsSurviveRestartAndReorderedDelivery() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        let id = try network.a.capture("fixture-protected")
        try network.exchange(rounds: 4)
        try network.a.clipboard.setFavorite(id: id, isFavorite: true)
        try network.b.clipboard.setPinned(id: id, isPinned: true)
        var settings = try XCTUnwrap(network.a.preferences.load())
        settings.clipboard.isRecordingEnabled = false
        try network.a.preferences.save(settings)
        try network.a.run()
        try network.b.run()
        let oldA = try network.a.delivery()
        let oldB = try network.b.delivery()
        try network.a.clipboard.setTags(id: id, tags: ["fixture-tag"])
        try network.a.run()
        try network.b.receive(network.a.delivery())
        try network.b.run()
        try network.b.receive(oldA)
        try network.a.receive(oldB)
        try network.restart()
        try network.exchange(rounds: 6)
        for device in [network.a, network.b] {
            let item = try XCTUnwrap(device.clipboard.item(id: id))
            XCTAssertTrue(item.isFavorite)
            XCTAssertTrue(item.isPinned)
            XCTAssertEqual(item.tags, ["fixture-tag"])
            XCTAssertEqual(try device.preferences.load()?.clipboard.isRecordingEnabled, false)
        }
        let before = try network.revisions()
        try network.exchange(rounds: 4)
        XCTAssertEqual(try network.revisions(), before)
    }

    func testResetGenerationCanReplacePreviousGenerationManifest() throws {
        let network = try SyncTestNetwork()
        defer { network.remove() }
        try network.exchange(rounds: 2)
        let descriptor = try network.a.store.readProtocol()
        let generation = try network.a.sync.advanceGeneration(storeID: descriptor.storeID)
        try network.a.store.writeReset(SyncResetMarker(deviceID: network.a.id, generation: generation, resetAt: Date()))
        try network.a.overrides.setReplicaRevision(0)
        try network.a.overrides.setSeenRevisions([:])
        try network.a.run()
        XCTAssertEqual(try network.a.store.replicas(generation: generation).first?.manifest.generation, generation)
    }
}

private final class SyncTestNetwork {
    let directory: URL
    var a: SyncTestDevice
    var b: SyncTestDevice

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SyncConvergence-\(UUID().uuidString)")
        a = try SyncTestDevice(directory: directory.appendingPathComponent("a"))
        b = try SyncTestDevice(directory: directory.appendingPathComponent("b"))
        _ = try a.store.prepare()
        try b.receive(["protocol.json": Data(contentsOf: a.root.appendingPathComponent("protocol.json"))])
        _ = try b.store.prepare()
    }

    func restart() throws {
        a = try SyncTestDevice(directory: a.directory)
        b = try SyncTestDevice(directory: b.directory)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func exchange(rounds: Int) throws {
        for _ in 0..<rounds {
            try a.run()
            try b.receive(a.delivery())
            try b.run()
            try a.receive(b.delivery())
        }
    }

    func revisions() throws -> [Int64] { try [a.overrides.replicaRevision(), b.overrides.replicaRevision()] }
}

private final class SyncTestDevice {
    let directory: URL
    let root: URL
    let clipboard: ClipboardRepository
    let preferences: PreferenceRepository
    let overrides: DeviceOverrideRepository
    let sync: SyncLocalRepository
    let runner: DriveSyncCycleRunner
    let files = SyncTestFileCoordinator()
    let id: String
    var store: DriveSyncStore { DriveSyncStore(rootURL: root, publicationLedger: sync.snapshotPublicationLedger) }

    init(directory: URL) throws {
        self.directory = directory
        root = directory.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try MacToolsDatabase.at(directory.appendingPathComponent("test.sqlite"))
        let payloads = PayloadStore(rootDirectory: directory.appendingPathComponent("payloads"))
        clipboard = ClipboardRepository(database: database, payloadStore: payloads)
        preferences = PreferenceRepository(database: database)
        if try preferences.load() == nil { try preferences.save(.defaults, enqueuesSyncChange: false) }
        overrides = DeviceOverrideRepository(database: database)
        id = try overrides.deviceID().uuidString
        sync = SyncLocalRepository(database: database, clipboardRepository: clipboard, preferenceRepository: preferences)
        let ledger = sync.snapshotPublicationLedger
        let files = self.files
        runner = DriveSyncCycleRunner(
            localRepository: sync, deviceOverrideRepository: overrides, payloadStore: payloads,
            currentDate: { Date(timeIntervalSince1970: 2_000_000_000) },
            deviceName: { "Fixture Mac" }, requestDownload: { _ in },
            makeStore: { DriveSyncStore(rootURL: $0, fileCoordinator: files, publicationLedger: ledger) }
        )
    }

    @discardableResult
    func run(forceWrite: Bool = false) throws -> DriveSyncCycleResult {
        try runner.run(rootURL: root, configuration: DriveSyncCycleConfiguration(
            historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes512
        ), forceWrite: forceWrite)
    }

    @discardableResult
    func capture(_ text: String, source: String = "Fixture", at date: Date = Date(timeIntervalSince1970: 100)) throws -> UUID {
        let id = UUID()
        try clipboard.upsert(ClipboardItem(
            id: id, kind: .text, displayTitle: text, searchableText: text, text: text,
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: source,
            contentHash: ClipboardContentHasher.sha256String(for: Data("text:\(text)".utf8)),
            createdAt: date, lastUsedAt: nil, useCount: 0,
            isPinned: false, isFavorite: false
        ))
        return id
    }

    func texts() throws -> [String] { try clipboard.search("", limit: 1_000).compactMap(\.text).sorted() }

    func delivery() throws -> [String: Data] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        var files: [String: Data] = [:]
        for case let path as String in enumerator {
            let url = root.appendingPathComponent(path)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            if path.hasPrefix("replicas/\(id)/") || path.hasPrefix("objects/") || path == "evictions/\(id).json" {
                files[path] = try Data(contentsOf: url)
            }
        }
        return files
    }

    func receive(_ files: [String: Data]) throws {
        for (path, data) in files.sorted(by: { $0.key > $1.key }) {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }
}

/// 故障由测试线程在两个同步周期之间设置；runner 的同步调用保持串行。
private final class SyncTestFileCoordinator: SyncFileCoordinating, @unchecked Sendable {
    enum Failure: Error { case beforePublication, afterPublication }
    var failure: Failure?
    var unavailableFileName: String?
    var beforePublication: (() throws -> Void)?
    var onManifestAccess: ((URL, Int) throws -> Void)? {
        didSet { accessCount = 0 }
    }
    private var accessCount = 0
    private let direct = DirectSyncFileCoordinator()

    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        if url.lastPathComponent == unavailableFileName { throw DriveSyncStoreError.itemNotDownloaded(url) }
        return try direct.readData(at: url, options: options)
    }

    func writeData(_ data: Data, to url: URL) throws { try direct.writeData(data, to: url) }

    func coordinateManifest(
        at url: URL, deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation
    ) throws -> SyncManifestMutationResult {
        accessCount += 1
        try onManifestAccess?(url, accessCount)
        var published = false
        let result = try direct.coordinateManifest(at: url) { versions in
            let decision = try mutation(versions)
            if case .publish = decision {
                published = true
                let beforePublication = self.beforePublication
                self.beforePublication = nil
                try beforePublication?()
                if failure == .beforePublication {
                    failure = nil
                    throw Failure.beforePublication
                }
            }
            return decision
        }
        if published, failure == .afterPublication {
            failure = nil
            throw Failure.afterPublication
        }
        return result
    }
}
