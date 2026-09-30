import Foundation
import XCTest
@testable import MacToolsCore

final class FavoriteOnlySyncTests: XCTestCase {
    func testLegacyAllHistoryScopeExportsOnlyFavorites() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let ordinary = try fixture.capture("fixture-ordinary", favorite: false)
        let pinned = try fixture.capture("fixture-pinned", favorite: false, pinned: true)
        let favorite = try fixture.capture("fixture-favorite", favorite: true)
        let bundle = try fixture.sync.exportBundle(
            deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory
        )
        XCTAssertEqual(bundle.clipboard.records.map(\.recordName), [favorite.uuidString])
        XCTAssertEqual(bundle.contents.count, 1)
        XCTAssertNotNil(try fixture.clipboard.item(id: ordinary))
        XCTAssertNotNil(try fixture.clipboard.item(id: pinned))
    }

    func testLegacySettingsNormalizeAndDoNotEncodeLimits() throws {
        for scope in ["allHistory", "favoritesAndPinned"] {
            let data = Data("{\"isEnabled\":true,\"clipboardScope\":\"\(scope)\",\"storageLimit\":2048}".utf8)
            let settings = try JSONDecoder().decode(SyncSettings.self, from: data)
            XCTAssertTrue(settings.isEnabled)
            XCTAssertEqual(settings.clipboardScope, .favoritesOnly)
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
            XCTAssertNil(encoded?["clipboardScope"])
            XCTAssertNil(encoded?["storageLimit"])
        }
        XCTAssertEqual(try JSONDecoder().decode(SyncSettings.self, from: Data("{}".utf8)), .defaults)
    }

    func testOldClipboardSnapshotDefaultsFavoriteRemovalsToEmpty() throws {
        let snapshot = SyncClipboardSnapshot(deviceID: "fixture", generation: 1, revision: 1, records: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: SyncSnapshotCodec.encode(snapshot)) as? [String: Any])
        json.removeValue(forKey: "favoriteRemovals")
        let decoded = try SyncSnapshotCodec.decode(SyncClipboardSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.favoriteRemovals, [])
    }

    func testOldOrdinaryAndPinnedRecordsAreNotImported() throws {
        let source = try FavoriteSyncFixture()
        let destination = try FavoriteSyncFixture(root: source.root)
        defer { source.remove(); destination.remove() }
        _ = try source.capture("fixture-legacy", favorite: true, pinned: true)
        var bundle = try source.sync.exportBundle(deviceID: source.id, generation: 1, revision: 1, scope: .allHistory)
        bundle.clipboard.records[0].isFavorite = false
        let contents = Dictionary(uniqueKeysWithValues: bundle.contents.map { ($0.contentID, $0.data) })
        try destination.sync.apply(clipboard: bundle.clipboard, contents: contents, payloadStore: destination.payloads, historyLimit: 500)
        XCTAssertTrue(try destination.clipboard.search("", limit: 10).isEmpty)
        _ = try DriveSyncStore(rootURL: source.root).write(bundle, seenRevisions: [source.id: 1], updatedAt: Date())
        guard case .synced = try destination.run().status else { return XCTFail("Legacy ordinary content should not be downloaded or imported") }
        XCTAssertTrue(try destination.clipboard.search("", limit: 10).isEmpty)
    }

    func testCancelFavoriteSurvivesPruningStalePeerAndRefavorite() throws {
        let first = try FavoriteSyncFixture()
        let second = try FavoriteSyncFixture(root: first.root)
        defer { first.remove(); second.remove() }
        let id = try first.capture("fixture-cancel", favorite: true)
        _ = try first.run()
        _ = try second.run()
        _ = try first.run()
        let stale = try XCTUnwrap(second.store.replicas(generation: 1).first { $0.manifest.deviceID == second.id })
        try first.clipboard.setFavorite(id: id, isFavorite: false, historyLimit: 0)
        XCTAssertNil(try first.clipboard.item(id: id))
        _ = try first.run()
        let published = try XCTUnwrap(first.store.replicas(generation: 1).first { $0.manifest.deviceID == first.id })
        XCTAssertTrue(published.clipboard.records.isEmpty)
        XCTAssertEqual(published.clipboard.favoriteRemovals.count, 1)
        let restartedSync = SyncLocalRepository(database: first.database, clipboardRepository: first.clipboard, preferenceRepository: first.preferences)
        let staleContents = try Dictionary(uniqueKeysWithValues: stale.clipboard.records.compactMap { record in
            try first.store.contentData(contentID: record.contentID, kind: record.kind).map { (record.contentID, $0) }
        })
        try restartedSync.apply(clipboard: stale.clipboard, contents: staleContents, payloadStore: first.payloads, historyLimit: 500)
        XCTAssertNil(try first.clipboard.item(id: id))
        _ = try second.run()
        XCTAssertFalse(try XCTUnwrap(second.clipboard.item(id: id)).isFavorite)
        XCTAssertTrue(try XCTUnwrap(second.store.replicas(generation: 1).first { $0.manifest.deviceID == second.id }).clipboard.records.isEmpty)
        let newID = try first.capture("fixture-cancel", favorite: false)
        try first.clipboard.setFavorite(id: newID, isFavorite: true)
        _ = try first.run()
        _ = try second.run()
        XCTAssertTrue(try XCTUnwrap(second.clipboard.search("", limit: 10).first).isFavorite)
    }

    func testFavoritesUploadWhenFolderExceedsEveryLegacyLimit() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let probe = fixture.root.appendingPathComponent("unrelated-space-probe")
        FileManager.default.createFile(atPath: probe.path, contents: nil)
        let handle = try FileHandle(forWritingTo: probe)
        try handle.truncate(atOffset: 3 * 1_024 * 1_024 * 1_024)
        try handle.close()
        let id = try fixture.capturePNG()
        let result = try fixture.run()
        guard case let .synced(_, usage) = result.status else { return XCTFail("Legacy quota still blocks favorite uploads") }
        XCTAssertGreaterThan(usage.usedBytes, SyncStorageLimit.gigabytes2.byteLimit)
        let snapshot = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        XCTAssertEqual(snapshot.clipboard.records.map(\.recordName), [id.uuidString])
        XCTAssertEqual(try fixture.store.storedObjects().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: probe.path))
    }

    func testFavoriteImageDescriptorAboveLegacySingleObjectLimitIsExported() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capturePNG()
        let item = try XCTUnwrap(fixture.clipboard.item(id: id))
        let bytes: Int64 = 65 * 1_024 * 1_024
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: try XCTUnwrap(item.cachedFilePath)))
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
        try fixture.database.writer.write { db in
            try db.execute(sql: "UPDATE payload_objects SET byteCount = ? WHERE id = ?", arguments: [bytes, try XCTUnwrap(item.payloadID)])
        }
        let draft = try fixture.sync.exportDraft(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        XCTAssertEqual(draft.clipboard.records.map(\.recordName), [id.uuidString])
        XCTAssertEqual(draft.contentDescriptors.first?.storedByteCount, bytes)
    }

    func testProtocolUpgradeIsRetryableAndBlocksLegacyReaders() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        var legacy = try fixture.store.readProtocol()
        legacy.protocolVersion = 1
        let protocolURL = fixture.root.appendingPathComponent("protocol.json")
        try SyncSnapshotCodec.encode(legacy).write(to: protocolURL, options: .atomic)
        XCTAssertThrowsError(try fixture.store.requireFavoritesOnlyProtocol(cancellation: .init(isCancelled: { true })))
        XCTAssertEqual(try fixture.store.readProtocol().protocolVersion, 1)
        let failingStore = DriveSyncStore(rootURL: fixture.root, fileCoordinator: RejectProtocolWrite())
        XCTAssertThrowsError(try failingStore.requireFavoritesOnlyProtocol())
        XCTAssertEqual(try fixture.store.readProtocol(), legacy)
        let upgraded = try fixture.store.requireFavoritesOnlyProtocol()
        XCTAssertEqual(upgraded.protocolVersion, 2)
        XCTAssertEqual(upgraded.storeID, legacy.storeID)
        XCTAssertEqual(try fixture.store.requireFavoritesOnlyProtocol(), upgraded)
        // v1 的 readProtocol 判定只接受版本 1；新版目录会触发其版本不兼容路径。
        XCTAssertThrowsError(try Self.legacyProtocolReader(at: protocolURL)) { error in
            XCTAssertEqual(error as? DriveSyncStoreError, .incompatibleProtocol(found: 2))
        }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: protocolURL)) as? [String: Any])
        XCTAssertNil(json["capacityLimit"])
    }

    func testMigratedOwnerReclaimsOrdinarySnapshotsAndObjectsAfterSafetyInterval() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capture("fixture-old-ordinary", favorite: true)
        var legacy = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        legacy.clipboard.records[0].isFavorite = false
        _ = try DriveSyncStore(rootURL: fixture.root).write(legacy, seenRevisions: [fixture.id: 1], updatedAt: Date())
        let oldReplica = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        let oldDirectory = fixture.root.appendingPathComponent("replicas/\(fixture.id)/revisions/\(try XCTUnwrap(oldReplica.manifest.snapshotDirectory))")
        let ancestor = try fixture.makeLegacyDirectory(bundle: legacy, revision: 0, name: "legacy-ordinary")
        try fixture.clipboard.setFavorite(id: id, isFavorite: false)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        _ = try fixture.run(now: now)
        let current = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        XCTAssertTrue(current.clipboard.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ancestor.path))
        XCTAssertEqual(try fixture.store.storedObjects().count, 1)
        _ = try fixture.run(now: now.addingTimeInterval(24 * 60 * 60 + 1))
        XCTAssertTrue(try fixture.store.storedObjects().isEmpty)
        XCTAssertNotNil(try fixture.clipboard.item(id: id))
    }

    func testLegacyCleanupPreservesUnknownIncompleteConcurrentAndUncoveredFavorites() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capture("fixture-protected", favorite: true)
        let bundle = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        _ = try fixture.run()
        let current = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        let unknown = try fixture.makeLegacyDirectory(bundle: bundle, revision: 0, name: "legacy-unknown")
        try Data([1]).write(to: unknown.appendingPathComponent("user-file"))
        let incomplete = try fixture.makeLegacyDirectory(bundle: bundle, revision: 0, name: "legacy-incomplete")
        try FileManager.default.removeItem(at: incomplete.appendingPathComponent("preferences.json"))
        let concurrent = try fixture.makeLegacyDirectory(bundle: bundle, revision: current.manifest.revision, name: "legacy-concurrent")
        var uncoveredBundle = bundle
        uncoveredBundle.clipboard.records[0].contentID = String(repeating: "a", count: 64)
        let uncovered = try fixture.makeLegacyDirectory(bundle: uncoveredBundle, revision: 0, name: "legacy-uncovered")
        XCTAssertEqual(try fixture.store.cleanupLegacySnapshots(supersededBy: current), 0)
        for directory in [unknown, incomplete, concurrent, uncovered] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        }
        XCTAssertNotNil(try fixture.clipboard.item(id: id))
    }

    func testOfflineLegacyPeerKeepsItsOnlyFavoriteAndOrdinaryReferencesUntilUpgrade() throws {
        let first = try FavoriteSyncFixture()
        let offline = try FavoriteSyncFixture(root: first.root)
        defer { first.remove(); offline.remove() }
        let favorite = try offline.capture("fixture-offline-favorite", favorite: true)
        _ = try offline.capture("fixture-offline-ordinary", favorite: true)
        var bundle = try offline.sync.exportBundle(deviceID: offline.id, generation: 1, revision: 1, scope: .allHistory)
        let ordinaryIndex = try XCTUnwrap(bundle.clipboard.records.firstIndex { $0.recordName != favorite.uuidString })
        bundle.clipboard.records[ordinaryIndex].isFavorite = false
        let ordinaryID = bundle.clipboard.records[ordinaryIndex].contentID
        _ = try DriveSyncStore(rootURL: first.root).write(bundle, seenRevisions: [offline.id: 1], updatedAt: Date())
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        _ = try first.run(now: now)
        _ = try first.run(now: now.addingTimeInterval(24 * 60 * 60 + 1))
        XCTAssertEqual(try first.clipboard.search("", limit: 10).count, 1)
        XCTAssertNotNil(try first.store.contentData(contentID: ordinaryID, kind: .text))
        let ordinaryLocal = try XCTUnwrap(offline.clipboard.search("", limit: 10).first { $0.id != favorite })
        try offline.clipboard.setFavorite(id: ordinaryLocal.id, isFavorite: false)
        _ = try offline.run(now: now.addingTimeInterval(24 * 60 * 60 + 2))
        _ = try first.run(now: now.addingTimeInterval(24 * 60 * 60 + 3))
        _ = try first.run(now: now.addingTimeInterval(48 * 60 * 60 + 4))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: try first.store.contentLocation(contentID: ordinaryID, kind: .text).path
        ))
        XCTAssertTrue(try first.store.replicas(generation: 1).allSatisfy { $0.clipboard.records.allSatisfy(\.isFavorite) })
        XCTAssertNotNil(try first.clipboard.item(id: favorite))
    }

    func testLegacyCleanupBatchAdvancesPastUnknownDirectoriesAndReportsExactBytes() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        _ = try fixture.capture("fixture-batch", favorite: true)
        _ = try fixture.run()
        let current = try XCTUnwrap(fixture.store.replicas(generation: 1).first)
        let bundle = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        for index in 0..<8 {
            let directory = try fixture.makeLegacyDirectory(bundle: bundle, revision: 0, name: String(format: "a-unknown-%02d", index))
            try Data([1]).write(to: directory.appendingPathComponent("user-file"))
        }
        let eligible = try fixture.makeLegacyDirectory(bundle: bundle, revision: 0, name: "z-eligible")
        let expectedBytes = try FileManager.default.contentsOfDirectory(at: eligible, includingPropertiesForKeys: [.fileSizeKey]).reduce(Int64(0)) {
            $0 + Int64(try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        var cursor: String?
        var reclaimed: Int64 = 0
        var completed = false
        for _ in 0..<10 {
            let batch = try fixture.store.cleanupLegacySnapshotBatch(supersededBy: current, afterDirectory: cursor, scanLimit: 2)
            reclaimed += batch.reclaimedBytes
            cursor = batch.lastScannedDirectory
            if batch.didComplete { completed = true; break }
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(reclaimed, expectedBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: eligible.path))
        for index in 0..<8 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("replicas/\(fixture.id)/revisions/\(String(format: "a-unknown-%02d", index))").path))
        }
    }

    func testStableRunnerDoesNotRepeatedlyDecodeUncoveredLegacyHistory() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        _ = try fixture.capture("fixture-stable", favorite: true)
        _ = try fixture.run()
        var bundle = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        bundle.clipboard.records[0].contentID = String(repeating: "a", count: 64)
        for index in 0..<40 {
            _ = try fixture.makeLegacyDirectory(bundle: bundle, revision: 0, name: String(format: "uncovered-%02d", index))
        }
        let files = LegacySnapshotReadCounter()
        let ledger = fixture.sync.snapshotPublicationLedger
        let runner = DriveSyncCycleRunner(
            localRepository: fixture.sync, deviceOverrideRepository: fixture.overrides, payloadStore: fixture.payloads,
            currentDate: { Date(timeIntervalSince1970: 2_000_000_000) }, deviceName: { "Fixture Mac" }, requestDownload: { _ in },
            makeStore: { DriveSyncStore(rootURL: $0, fileCoordinator: files, publicationLedger: ledger) }
        )
        let configuration = DriveSyncCycleConfiguration(historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes256)
        for _ in 0..<10 { _ = try runner.run(rootURL: fixture.root, configuration: configuration) }
        let reads = files.legacyReads
        XCTAssertGreaterThan(reads, 0)
        XCTAssertLessThanOrEqual(reads, 40)
        for _ in 0..<3 { _ = try runner.run(rootURL: fixture.root, configuration: configuration) }
        XCTAssertEqual(files.legacyReads, reads)
        runner.invalidateObservationCache()
        _ = try runner.run(rootURL: fixture.root, configuration: configuration)
        XCTAssertGreaterThan(files.legacyReads, reads)
    }

    func testIncompleteRetainedSnapshotPreventsGCUntilLateFavoriteEvidenceArrives() throws {
        for missingFile in ["clipboard.json", "preferences.json", "tombstones.json"] {
            let fixture = try FavoriteSyncFixture()
            defer { fixture.remove() }
            let id = try fixture.capture("fixture-late-proof", favorite: true)
            var oldBundle = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
            let contentID = try XCTUnwrap(oldBundle.clipboard.records.first?.contentID)
            // 尚未被当前取消时钟覆盖的离线收藏证据，其载荷只由迟到旧快照引用。
            oldBundle.clipboard.records[0].favoriteClock = .init(counter: 99, deviceID: fixture.id)
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            _ = try fixture.run(now: now)
            try fixture.clipboard.setFavorite(id: id, isFavorite: false)
            _ = try fixture.run(now: now)
            let delayed = try fixture.makeLegacyDirectory(bundle: oldBundle, revision: 0, name: "delayed-proof")
            let missingURL = delayed.appendingPathComponent(missingFile)
            let delayedData = try Data(contentsOf: missingURL)
            try FileManager.default.removeItem(at: missingURL)
            _ = try fixture.run(now: now.addingTimeInterval(24 * 60 * 60 + 1))
            XCTAssertNotNil(try fixture.store.contentData(contentID: contentID, kind: .text), missingFile)
            XCTAssertTrue(FileManager.default.fileExists(atPath: delayed.path))
            try delayedData.write(to: missingURL, options: .atomic)
            _ = try fixture.run(now: now.addingTimeInterval(24 * 60 * 60 + 2))
            XCTAssertNotNil(try fixture.store.contentData(contentID: contentID, kind: .text), missingFile)
            XCTAssertTrue(try fixture.store.retainedSnapshotContentIDs().contains(contentID))
        }
    }

    func testRemoteFavoriteRemovalAppliesFiveHundredItemLimitBeforePruning() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let canceled = try fixture.capture("fixture-old-favorite", favorite: true, at: Date(timeIntervalSince1970: 0))
        let oldBundle = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        for index in 0..<500 {
            _ = try fixture.capture("fixture-normal-\(index)", favorite: false, at: Date(timeIntervalSince1970: Double(200 + index)))
        }
        let pinned = try fixture.capture("fixture-pinned-protection", favorite: false, pinned: true)
        let favorite = try fixture.capture("fixture-favorite-protection", favorite: true)
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
        let contentID = try XCTUnwrap(oldBundle.clipboard.records.first?.contentID)
        try fixture.sync.apply(
            clipboard: .init(deviceID: "peer", generation: 1, revision: 2, records: [],
                             favoriteRemovals: [.init(contentID: contentID, favoriteClock: .init(counter: 1, deviceID: "peer"))]),
            contents: [:], payloadStore: fixture.payloads, historyLimit: 500
        )
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
        XCTAssertNil(try fixture.clipboard.item(id: canceled))
        XCTAssertTrue(try XCTUnwrap(fixture.clipboard.item(id: pinned)).isPinned)
        XCTAssertTrue(try XCTUnwrap(fixture.clipboard.item(id: favorite)).isFavorite)
        XCTAssertEqual(try fixture.sync.favoriteRemovals(generation: 1).first { $0.contentID == contentID }?.favoriteClock.counter, 1)
        let contents = Dictionary(uniqueKeysWithValues: oldBundle.contents.map { ($0.contentID, $0.data) })
        try fixture.sync.apply(clipboard: oldBundle.clipboard, contents: contents, payloadStore: fixture.payloads, historyLimit: 500)
        XCTAssertNil(try fixture.clipboard.item(id: canceled))
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
    }

    func testBatchRemoteFavoriteRemovalsPrunePayloadsAndPreserveProtectionAndClocks() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let canceledText = try fixture.capture("fixture-batch-text", favorite: true, at: Date(timeIntervalSince1970: 0))
        let canceledPNG = try fixture.capturePNG()
        let pngItem = try XCTUnwrap(fixture.clipboard.item(id: canceledPNG))
        let pngPath = try XCTUnwrap(pngItem.cachedFilePath)
        let pinned = try fixture.capture("fixture-batch-pinned", favorite: true, pinned: true)
        let protected = try fixture.capture("fixture-batch-protected", favorite: true)
        for index in 0..<3 {
            _ = try fixture.capture("fixture-batch-normal-\(index)", favorite: false, at: Date(timeIntervalSince1970: Double(300 + index)))
        }
        let oldBundle = try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 1, scope: .allHistory)
        let removedNames = Set([canceledText, canceledPNG, pinned].map(\.uuidString))
        let removals = oldBundle.clipboard.records.filter { removedNames.contains($0.recordName) }.map {
            SyncFavoriteRemoval(contentID: $0.contentID, favoriteClock: .init(counter: 1, deviceID: "peer"))
        }
        try fixture.sync.applyFavoriteRemovals(removals, generation: 1, historyLimit: 3)
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 3)
        XCTAssertNil(try fixture.clipboard.item(id: canceledText))
        XCTAssertNil(try fixture.clipboard.item(id: canceledPNG))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pngPath))
        XCTAssertTrue(try XCTUnwrap(fixture.clipboard.item(id: pinned)).isPinned)
        XCTAssertFalse(try XCTUnwrap(fixture.clipboard.item(id: pinned)).isFavorite)
        XCTAssertTrue(try XCTUnwrap(fixture.clipboard.item(id: protected)).isFavorite)
        let restarted = SyncLocalRepository(database: fixture.database, clipboardRepository: fixture.clipboard, preferenceRepository: fixture.preferences)
        XCTAssertEqual(try restarted.favoriteRemovals(generation: 1).sorted { $0.contentID < $1.contentID }, removals.sorted { $0.contentID < $1.contentID })
        let contents = Dictionary(uniqueKeysWithValues: oldBundle.contents.map { ($0.contentID, $0.data) })
        try restarted.apply(clipboard: oldBundle.clipboard, contents: contents, payloadStore: fixture.payloads, historyLimit: 3)
        XCTAssertNil(try fixture.clipboard.item(id: canceledText))
        XCTAssertNil(try fixture.clipboard.item(id: canceledPNG))
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 3)
    }

    func testSameSnapshotCancellationMustPreserveNewerLocalTagsBeforeRefavorite() throws {
        for containsRemoval in [false, true] {
            let fixture = try FavoriteSyncFixture()
            defer { fixture.remove() }
            let id = try fixture.capture("fixture-probe-refavorite-snapshot", favorite: true, at: Date(timeIntervalSince1970: 100))
            try fixture.clipboard.setFavorite(id: id, isFavorite: true)
            for _ in 0..<5 { try fixture.clipboard.setTags(id: id, tags: ["local-new"]) }
            let localBefore = try XCTUnwrap(fixture.clipboard.item(id: id))
            XCTAssertEqual(localBefore.favoriteClock.counter, 1)
            XCTAssertEqual(localBefore.tagsClock.counter, 5)
            for index in 0..<500 {
                _ = try fixture.capture("fixture-probe-newer-ordinary-\(index)", favorite: false, at: Date(timeIntervalSince1970: Double(200 + index)))
            }
            var bundle = try fixture.sync.exportBundle(deviceID: "probe-refavorite-peer", generation: 1, revision: 1, scope: .allHistory)
            let original = try XCTUnwrap(bundle.clipboard.records.first)
            bundle.clipboard.records[0].favoriteClock = .init(counter: 3, deviceID: "probe-refavorite-peer")
            bundle.clipboard.records[0].tags = []
            bundle.clipboard.records[0].tagsClock = .zero
            if containsRemoval {
                bundle.clipboard.favoriteRemovals = [.init(contentID: original.contentID, favoriteClock: .init(counter: 2, deviceID: "probe-cancel-peer"))]
            }
            let contents = Dictionary(uniqueKeysWithValues: bundle.contents.map { ($0.contentID, $0.data) })
            try fixture.sync.apply(clipboard: bundle.clipboard, contents: contents, payloadStore: fixture.payloads, historyLimit: 500)
            let merged = try XCTUnwrap(fixture.clipboard.item(id: id))
            XCTAssertTrue(merged.isFavorite)
            XCTAssertEqual(merged.favoriteClock.counter, 3)
            XCTAssertEqual(merged.tags, ["local-new"], "containsRemoval=\(containsRemoval): newer independent local tags must survive")
            XCTAssertEqual(merged.tagsClock, localBefore.tagsClock, "containsRemoval=\(containsRemoval): newer local tag clock must survive")
        }
    }

    func testRunnerTwoPeersCancellationMustPreserveLocalFieldsBeforeRefavorite() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capture("fixture-probe-runner-refavorite", favorite: true, at: Date(timeIntervalSince1970: 100))
        try fixture.clipboard.setFavorite(id: id, isFavorite: true)
        for _ in 0..<5 {
            try fixture.clipboard.setTags(id: id, tags: ["local-new"])
            try fixture.clipboard.setPinned(id: id, isPinned: false)
        }
        let localBefore = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertEqual(localBefore.favoriteClock.counter, 1)
        XCTAssertEqual(localBefore.tagsClock.counter, 5)
        XCTAssertEqual(localBefore.pinnedClock.counter, 5)
        for index in 0..<500 {
            _ = try fixture.capture("fixture-probe-runner-ordinary-\(index)", favorite: false, at: Date(timeIntervalSince1970: Double(200 + index)))
        }
        var cancel = try fixture.sync.exportBundle(deviceID: "probe-cancel-peer", generation: 1, revision: 1, scope: .allHistory)
        var refavorite = try fixture.sync.exportBundle(deviceID: "probe-refavorite-peer", generation: 1, revision: 1, scope: .allHistory)
        let original = try XCTUnwrap(refavorite.clipboard.records.first)
        cancel.clipboard.records = []
        cancel.clipboard.favoriteRemovals = [.init(contentID: original.contentID, favoriteClock: .init(counter: 2, deviceID: "probe-cancel-peer"))]
        cancel.contents = []
        refavorite.clipboard.records[0].favoriteClock = .init(counter: 3, deviceID: "probe-refavorite-peer")
        refavorite.clipboard.records[0].tags = ["old-tag"]
        refavorite.clipboard.records[0].tagsClock = .init(counter: 1, deviceID: "probe-refavorite-peer")
        refavorite.clipboard.records[0].isPinned = true
        refavorite.clipboard.records[0].pinnedClock = .init(counter: 1, deviceID: "probe-refavorite-peer")
        _ = try fixture.store.write(cancel, seenRevisions: ["probe-cancel-peer": 1], updatedAt: Date(timeIntervalSince1970: 1_000))
        _ = try fixture.store.write(refavorite, seenRevisions: ["probe-refavorite-peer": 1], updatedAt: Date(timeIntervalSince1970: 1_000))
        let result = try fixture.run()
        guard case .synced = result.status else { XCTFail("Synthetic runner must complete a real two-peer sync"); return }
        let merged = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertTrue(merged.isFavorite)
        XCTAssertEqual(merged.favoriteClock.counter, 3)
        XCTAssertEqual(merged.tags, ["local-new"], "same-cycle cancellation must not discard newer local tags")
        XCTAssertEqual(merged.tagsClock, localBefore.tagsClock)
        XCTAssertFalse(merged.isPinned, "same-cycle cancellation must not discard newer local unpin")
        XCTAssertEqual(merged.pinnedClock, localBefore.pinnedClock)
    }

    func testIncompleteSnapshotPreservesFieldsThroughForegroundPruningAndRetry() throws {
        for corruptContent in [false, true] {
            let fixture = try FavoriteSyncFixture()
            defer { fixture.remove() }
            let id = try fixture.capture("fixture-incomplete-refavorite", favorite: true)
            let before = try fixture.prepareIndependentFieldsAndFullHistory(id: id)
            let bundle = try fixture.refavoriteBundle(id: id)
            let content = try XCTUnwrap(bundle.contents.first)
            if corruptContent {
                XCTAssertThrowsError(try fixture.sync.apply(
                    clipboard: bundle.clipboard, contents: [content.contentID: Data("invalid-json".utf8)],
                    payloadStore: fixture.payloads, historyLimit: 500
                ))
            } else {
                try fixture.sync.apply(clipboard: bundle.clipboard, contents: [:], payloadStore: fixture.payloads, historyLimit: 500)
            }
            _ = try fixture.capture("fixture-foreground-pressure", favorite: false, at: Date(timeIntervalSince1970: 1_000))
            _ = try fixture.clipboard.enforceHistoryLimit(500)
            let pending = try XCTUnwrap(fixture.clipboard.item(id: id))
            XCTAssertTrue(pending.isFavorite)
            XCTAssertEqual(pending.favoriteClock.counter, 3)
            XCTAssertEqual(pending.tagsClock, before.tagsClock)
            XCTAssertEqual(pending.pinnedClock, before.pinnedClock)
            try fixture.sync.apply(
                clipboard: bundle.clipboard, contents: [content.contentID: content.data],
                payloadStore: fixture.payloads, historyLimit: 500
            )
            let merged = try XCTUnwrap(fixture.clipboard.item(id: id))
            XCTAssertEqual(merged.tags, ["local-new"])
            XCTAssertEqual(merged.tagsClock, before.tagsClock)
            XCTAssertFalse(merged.isPinned)
            XCTAssertEqual(merged.pinnedClock, before.pinnedClock)
            XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
        }
    }

    func testEarlierContentGroupDoesNotPruneRefavoriteFieldsBeforeLaterMerge() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capture("fixture-ordered-refavorite", favorite: true)
        let before = try fixture.prepareIndependentFieldsAndFullHistory(id: id)
        var bundle = try fixture.refavoriteBundle(id: id)
        let original = try XCTUnwrap(bundle.clipboard.records.first)
        let earlierText = "fixture-ordered-new-favorite-0"
        let earlierID = ClipboardContentHasher.sha256String(for: Data("text:\(earlierText)".utf8))
        XCTAssertLessThan(earlierID, original.contentID, "Runner must import this distinct content group first")
        var earlierRecord = original
        earlierRecord.recordName = UUID().uuidString
        earlierRecord.contentID = earlierID
        earlierRecord.displayTitle = earlierText
        earlierRecord.searchableText = earlierText
        bundle.clipboard.records.append(earlierRecord)
        bundle.contents.append(.init(contentID: earlierID, kind: .text, data: try SyncSnapshotCodec.encode(
            SyncTextContentObject(contentID: earlierID, kind: .text, text: earlierText, byteCount: Int64(Data(earlierText.utf8).count))
        )))
        _ = try fixture.store.write(bundle, seenRevisions: [bundle.clipboard.deviceID: 1], updatedAt: Date(timeIntervalSince1970: 1_000))
        guard case .synced = try fixture.run().status else { return XCTFail("All content groups must finish before pruning") }
        XCTAssertNotNil(try fixture.clipboard.item(id: try XCTUnwrap(UUID(uuidString: earlierRecord.recordName))))
        let merged = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertEqual(merged.tags, ["local-new"])
        XCTAssertEqual(merged.tagsClock, before.tagsClock)
        XCTAssertFalse(merged.isPinned)
        XCTAssertEqual(merged.pinnedClock, before.pinnedClock)
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
    }

    func testRunnerMissingRefavoritePayloadPreservesFieldsThroughCaptureAndRetry() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capturePNG()
        let before = try fixture.prepareIndependentFieldsAndFullHistory(id: id)
        let bundle = try fixture.refavoriteBundle(id: id)
        let content = try XCTUnwrap(bundle.contents.first)
        _ = try fixture.store.write(bundle, seenRevisions: [bundle.clipboard.deviceID: 1], updatedAt: Date(timeIntervalSince1970: 1_000))
        let sharedURL = try fixture.store.contentLocation(contentID: content.contentID, kind: content.kind)
        try FileManager.default.removeItem(at: sharedURL)
        try FileManager.default.removeItem(atPath: try XCTUnwrap(before.cachedFilePath))
        guard case .waitingForDownload = try fixture.run().status else { return XCTFail("Missing newer favorite payload must remain retryable") }
        XCTAssertTrue(try fixture.sync.hasPendingChanges(), "Unavailable local favorite must remain in the outbox")
        _ = try fixture.capture("fixture-missing-payload-foreground", favorite: false, at: Date(timeIntervalSince1970: 1_000))
        _ = try fixture.clipboard.enforceHistoryLimit(500)
        let pending = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertTrue(pending.isFavorite)
        XCTAssertEqual(pending.favoriteClock.counter, 3)
        XCTAssertEqual(pending.tagsClock, before.tagsClock)
        XCTAssertEqual(pending.pinnedClock, before.pinnedClock)
        try content.data.write(to: sharedURL, options: .atomic)
        guard case .synced = try fixture.run().status else { return XCTFail("Downloaded payload must complete the deferred import") }
        let merged = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertEqual(merged.tags, ["local-new"])
        XCTAssertEqual(merged.tagsClock, before.tagsClock)
        XCTAssertFalse(merged.isPinned)
        XCTAssertEqual(merged.pinnedClock, before.pinnedClock)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(merged.cachedFilePath)))
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
        XCTAssertTrue(try fixture.sync.exportDraft(deviceID: fixture.id, generation: 1, revision: 3, scope: .allHistory).unavailableClipboardRecordNames.isEmpty)
        XCTAssertFalse(try fixture.sync.hasPendingChanges(), "Restored and published favorite must be acknowledged in the same cycle")
    }

    func testRunnerCancellationAfterFavoritePremergePreservesFieldsForRetry() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capturePNG()
        let before = try fixture.prepareIndependentFieldsAndFullHistory(id: id)
        let bundle = try fixture.refavoriteBundle(id: id)
        let content = try XCTUnwrap(bundle.contents.first)
        _ = try fixture.store.write(bundle, seenRevisions: [bundle.clipboard.deviceID: 1], updatedAt: Date(timeIntervalSince1970: 1_000))
        let sharedURL = try fixture.store.contentLocation(contentID: content.contentID, kind: content.kind)
        try FileManager.default.removeItem(at: sharedURL)
        try FileManager.default.removeItem(atPath: try XCTUnwrap(before.cachedFilePath))
        let cancellation = FavoriteSyncCancellationFlag()
        XCTAssertThrowsError(try fixture.run(
            requestDownload: { _ in cancellation.cancel() },
            cancellation: .init(isCancelled: { cancellation.isCancelled })
        )) { error in
            XCTAssertEqual(error as? SyncCycleCancellationError, .cancelled)
        }
        XCTAssertTrue(try fixture.sync.hasPendingChanges(), "Cancelled cycle must not acknowledge local changes")
        _ = try fixture.capture("fixture-cancelled-foreground", favorite: false, at: Date(timeIntervalSince1970: 1_000))
        _ = try fixture.clipboard.enforceHistoryLimit(500)
        let pending = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertTrue(pending.isFavorite)
        XCTAssertEqual(pending.tagsClock, before.tagsClock)
        XCTAssertEqual(pending.pinnedClock, before.pinnedClock)
        XCTAssertEqual(try fixture.sync.favoriteRemovals(generation: 1).first?.favoriteClock.counter, 2)
        try content.data.write(to: sharedURL, options: .atomic)
        guard case .synced = try fixture.run().status else { return XCTFail("A new cycle must complete after cancellation") }
        let merged = try XCTUnwrap(fixture.clipboard.item(id: id))
        XCTAssertEqual(merged.tags, ["local-new"])
        XCTAssertEqual(merged.tagsClock, before.tagsClock)
        XCTAssertFalse(merged.isPinned)
        XCTAssertEqual(merged.pinnedClock, before.pinnedClock)
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
        XCTAssertTrue(try fixture.sync.exportDraft(deviceID: fixture.id, generation: 1, revision: 2, scope: .allHistory).unavailableClipboardRecordNames.isEmpty)
        XCTAssertFalse(try fixture.sync.hasPendingChanges())
    }

    func testUnrestoredLocalPayloadRemainsFailedAndPendingAfterFinalExport() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capturePNG()
        let before = try XCTUnwrap(fixture.clipboard.item(id: id))
        try FileManager.default.removeItem(atPath: try XCTUnwrap(before.cachedFilePath))
        guard case .failed = try fixture.run().status else { return XCTFail("A payload still unavailable after merging must not report success") }
        XCTAssertTrue(try fixture.sync.hasPendingChanges())
        XCTAssertEqual(try fixture.sync.exportDraft(deviceID: fixture.id, generation: 1, revision: 2, scope: .allHistory).unavailableClipboardRecordNames, [id.uuidString])
        XCTAssertTrue(try XCTUnwrap(fixture.store.replicas(generation: 1).first { $0.manifest.deviceID == fixture.id }).clipboard.records.isEmpty)
    }

    func testPersistedNewerCancellationRejectsLateFavoriteForRecapturedContent() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capture("fixture-persisted-cancel-refavorite", favorite: true)
        var bundle = try fixture.refavoriteBundle(id: id)
        let content = try XCTUnwrap(bundle.contents.first)
        let removal = SyncFavoriteRemoval(contentID: content.contentID, favoriteClock: .init(counter: 4, deviceID: "cancel-peer"))
        try fixture.sync.applyFavoriteRemovals([removal], generation: 1, historyLimit: 0)
        XCTAssertNil(try fixture.clipboard.item(id: id))
        let recapturedID = try fixture.capture("fixture-persisted-cancel-refavorite", favorite: false)
        bundle.clipboard.favoriteRemovals = []
        try fixture.sync.apply(
            clipboard: bundle.clipboard, contents: [content.contentID: content.data],
            payloadStore: fixture.payloads, historyLimit: 500
        )
        let item = try XCTUnwrap(fixture.clipboard.item(id: recapturedID))
        XCTAssertFalse(item.isFavorite)
        XCTAssertEqual(item.favoriteClock, .zero)
        XCTAssertEqual(try fixture.sync.favoriteRemovals(generation: 1), [removal])
        XCTAssertTrue(try fixture.sync.exportBundle(deviceID: fixture.id, generation: 1, revision: 2, scope: .allHistory).clipboard.records.isEmpty)
    }

    func testNewerCancellationWinsOverRefavoriteAndPrunesOnlyAfterCompleteImport() throws {
        let fixture = try FavoriteSyncFixture()
        defer { fixture.remove() }
        let id = try fixture.capture("fixture-latest-cancellation", favorite: true)
        _ = try fixture.prepareIndependentFieldsAndFullHistory(id: id)
        var bundle = try fixture.refavoriteBundle(id: id)
        let content = try XCTUnwrap(bundle.contents.first)
        let removal = SyncFavoriteRemoval(contentID: content.contentID, favoriteClock: .init(counter: 4, deviceID: "cancel-peer"))
        bundle.clipboard.favoriteRemovals = [removal]
        try fixture.sync.apply(
            clipboard: bundle.clipboard, contents: [content.contentID: content.data],
            payloadStore: fixture.payloads, historyLimit: 500
        )
        XCTAssertNil(try fixture.clipboard.item(id: id))
        XCTAssertEqual(try fixture.clipboard.countNormalItems(), 500)
        XCTAssertEqual(try fixture.sync.favoriteRemovals(generation: 1), [removal])
    }

    private static func legacyProtocolReader(at url: URL) throws -> SyncProtocolDescriptor {
        let descriptor = try SyncSnapshotCodec.decode(SyncProtocolDescriptor.self, from: Data(contentsOf: url))
        guard descriptor.protocolVersion == 1 else { throw DriveSyncStoreError.incompatibleProtocol(found: descriptor.protocolVersion) }
        return descriptor
    }

    func testUsagePresentationAlwaysUsesMegabytesWithoutHistoryOrQuota() {
        XCTAssertEqual(SyncStorageUsage.formattedUsedMegabytes(0), "已占用 0.0 MB")
        XCTAssertEqual(SyncStorageUsage.formattedUsedMegabytes(64), "已占用 < 0.1 MB")
        XCTAssertEqual(SyncStorageUsage.formattedUsedMegabytes(3 * 1_024 * 1_024 * 1_024), "已占用 3072.0 MB")
    }

}

private final class FavoriteSyncFixture {
    let directory: URL
    let root: URL
    let database: MacToolsDatabase
    let payloads: PayloadStore
    let clipboard: ClipboardRepository
    let preferences: PreferenceRepository
    let overrides: DeviceOverrideRepository
    let sync: SyncLocalRepository
    let id: String
    var store: DriveSyncStore { DriveSyncStore(rootURL: root, publicationLedger: sync.snapshotPublicationLedger) }

    init(root: URL? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FavoriteOnlySyncTests-\(UUID().uuidString)")
        self.root = root ?? directory.appendingPathComponent("cloud")
        database = try MacToolsDatabase.inMemory()
        payloads = PayloadStore(rootDirectory: directory.appendingPathComponent("payloads"))
        clipboard = ClipboardRepository(database: database, payloadStore: payloads)
        preferences = PreferenceRepository(database: database)
        try preferences.save(.defaults, enqueuesSyncChange: false)
        overrides = DeviceOverrideRepository(database: database)
        id = try overrides.deviceID().uuidString
        sync = SyncLocalRepository(database: database, clipboardRepository: clipboard, preferenceRepository: preferences)
        let descriptor = try store.prepare()
        try sync.bindStore(descriptor.storeID)
    }

    @discardableResult
    func capture(_ text: String, favorite: Bool, pinned: Bool = false, at date: Date = Date(timeIntervalSince1970: 100)) throws -> UUID {
        let id = UUID()
        try clipboard.upsert(ClipboardItem(
            id: id, kind: .text, displayTitle: text, searchableText: text, text: text,
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: "Fixture",
            contentHash: ClipboardContentHasher.sha256String(for: Data("text:\(text)".utf8)),
            createdAt: date, lastUsedAt: nil, useCount: 0,
            isPinned: pinned, isFavorite: favorite
        ))
        return id
    }

    func run(
        now: Date = Date(timeIntervalSince1970: 2_000_000_000),
        requestDownload: @escaping DriveSyncCycleRunner.DownloadRequester = { _ in },
        cancellation: SyncCycleCancellation = SyncCycleCancellation()
    ) throws -> DriveSyncCycleResult {
        let ledger = sync.snapshotPublicationLedger
        let runner = DriveSyncCycleRunner(
            localRepository: sync, deviceOverrideRepository: overrides, payloadStore: payloads,
            currentDate: { now }, deviceName: { "Fixture Mac" }, requestDownload: requestDownload,
            makeStore: { DriveSyncStore(rootURL: $0, publicationLedger: ledger) }
        )
        return try runner.run(rootURL: root, configuration: .init(
            historyLimit: 500, clipboardScope: .allHistory, storageLimit: .megabytes256
        ), cancellation: cancellation)
    }

    func prepareIndependentFieldsAndFullHistory(id: UUID) throws -> ClipboardItem {
        try clipboard.setFavorite(id: id, isFavorite: true)
        for _ in 0..<5 {
            try clipboard.setTags(id: id, tags: ["local-new"])
            try clipboard.setPinned(id: id, isPinned: false)
        }
        for index in 0..<500 {
            _ = try capture("fixture-pressure-ordinary-\(index)", favorite: false, at: Date(timeIntervalSince1970: Double(200 + index)))
        }
        return try XCTUnwrap(clipboard.item(id: id))
    }

    func refavoriteBundle(id: UUID) throws -> SyncExportBundle {
        var bundle = try sync.exportBundle(deviceID: "refavorite-peer", generation: 1, revision: 1, scope: .allHistory)
        let index = try XCTUnwrap(bundle.clipboard.records.firstIndex { $0.recordName == id.uuidString })
        bundle.clipboard.records[index].favoriteClock = .init(counter: 3, deviceID: "refavorite-peer")
        bundle.clipboard.records[index].tags = ["old-tag"]
        bundle.clipboard.records[index].tagsClock = .init(counter: 1, deviceID: "refavorite-peer")
        bundle.clipboard.records[index].isPinned = true
        bundle.clipboard.records[index].pinnedClock = .init(counter: 1, deviceID: "refavorite-peer")
        bundle.clipboard.favoriteRemovals = [.init(
            contentID: bundle.clipboard.records[index].contentID,
            favoriteClock: .init(counter: 2, deviceID: "cancel-peer")
        )]
        return bundle
    }

    @discardableResult
    func capturePNG() throws -> UUID {
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let id = UUID()
        try clipboard.upsertPNG(ClipboardItem(
            id: id, kind: .imageData, displayTitle: "Fixture PNG", searchableText: "Fixture PNG", text: nil,
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: "Fixture",
            contentHash: ClipboardContentHasher.sha256String(for: data), createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil, useCount: 0, isPinned: false, isFavorite: true
        ), data: data)
        return id
    }

    func makeLegacyDirectory(bundle: SyncExportBundle, revision: Int64, name: String) throws -> URL {
        let directory = root.appendingPathComponent("replicas/\(id)/revisions/\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var clipboard = bundle.clipboard
        var preferences = bundle.preferences
        var tombstones = bundle.tombstones
        clipboard.revision = revision
        preferences.revision = revision
        tombstones.revision = revision
        try SyncSnapshotCodec.encode(clipboard).write(to: directory.appendingPathComponent("clipboard.json"))
        try SyncSnapshotCodec.encode(preferences).write(to: directory.appendingPathComponent("preferences.json"))
        try SyncSnapshotCodec.encode(tombstones).write(to: directory.appendingPathComponent("tombstones.json"))
        return directory
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private final class FavoriteSyncCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

private struct RejectProtocolWrite: SyncFileCoordinating {
    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        try DirectSyncFileCoordinator().readData(at: url, options: options)
    }
    func writeData(_ data: Data, to url: URL) throws {
        if url.lastPathComponent == "protocol.json" { throw CocoaError(.fileWriteUnknown) }
        try DirectSyncFileCoordinator().writeData(data, to: url)
    }
    func coordinateManifest(at url: URL, deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation) throws -> SyncManifestMutationResult {
        try DirectSyncFileCoordinator().coordinateManifest(at: url, deciding: mutation)
    }
}

private final class LegacySnapshotReadCounter: SyncFileCoordinating, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var legacyReads: Int { lock.withLock { reads } }

    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        if url.lastPathComponent == "clipboard.json", url.deletingLastPathComponent().lastPathComponent.hasPrefix("uncovered-") {
            lock.withLock { reads += 1 }
        }
        return try DirectSyncFileCoordinator().readData(at: url, options: options)
    }
    func writeData(_ data: Data, to url: URL) throws {
        try DirectSyncFileCoordinator().writeData(data, to: url)
    }
    func coordinateManifest(at url: URL, deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation) throws -> SyncManifestMutationResult {
        try DirectSyncFileCoordinator().coordinateManifest(at: url, deciding: mutation)
    }
}
