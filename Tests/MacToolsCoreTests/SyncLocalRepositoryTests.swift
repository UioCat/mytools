import Foundation
import XCTest
@testable import MacToolsCore

final class SyncLocalRepositoryTests: XCTestCase {
    func testTwoDatabasesConvergeThroughSharedSnapshotAndContentObject() throws {
        let root = temporaryDirectory().appendingPathComponent("MacTools Sync", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let store = DriveSyncStore(rootURL: root)
        let descriptor = try store.prepare()
        let first = try makeReplica(deviceID: "device-a")
        let second = try makeReplica(deviceID: "device-b")
        defer {
            try? FileManager.default.removeItem(at: first.workingDirectory)
            try? FileManager.default.removeItem(at: second.workingDirectory)
        }
        try first.sync.bindStore(descriptor.storeID)
        try second.sync.bindStore(descriptor.storeID)

        let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000000")!
        let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000000")!
        try first.clipboard.upsert(textItem(id: firstID, text: "shared text"))
        try second.clipboard.upsert(textItem(id: secondID, text: "shared text"))
        var firstSettings = AppSettings.defaults
        firstSettings.appearanceMode = .dark
        firstSettings.translation.apiKey = "must-not-sync"
        try first.preferences.save(firstSettings)

        let firstBundle = try first.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 1,
            scope: .allHistory
        )
        _ = try store.write(firstBundle, seenRevisions: ["device-a": 1], updatedAt: Date())
        let remote = try XCTUnwrap(store.replicas(generation: 1).first)
        let contents = try Dictionary(uniqueKeysWithValues: remote.clipboard.records.compactMap { record in
            try store.contentData(contentID: record.contentID, kind: record.kind).map {
                (record.contentID, $0)
            }
        })
        try second.sync.apply(
            clipboard: remote.clipboard,
            contents: contents,
            payloadStore: second.payloadStore,
            historyLimit: 500
        )
        let mergedSettings = try second.sync.apply(preferences: remote.preferences)

        let items = try second.clipboard.search("", limit: 500)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, firstID)
        XCTAssertEqual(items[0].text, "shared text")
        XCTAssertEqual(mergedSettings?.appearanceMode, .dark)
        XCTAssertEqual(mergedSettings?.translation.apiKey, "")
        XCTAssertFalse(firstBundle.preferences.domains.contains {
            String(data: $0.value, encoding: .utf8)?.contains("must-not-sync") == true
        })
        XCTAssertEqual(try store.storedObjects().count, 1)
    }

    func testRepeatedExportsWithStableCutoffRemainEquivalent() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        try replica.clipboard.upsert(textItem(id: UUID(), text: "stable text"))
        let imageData = Self.pngData()
        let image = ClipboardItem(
            id: UUID(),
            kind: .imageData,
            displayTitle: "stable image",
            searchableText: "stable image",
            text: nil,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "Tests",
            contentHash: ClipboardContentHasher.sha256String(for: imageData),
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        try replica.clipboard.upsertPNG(image, data: imageData)
        let cutoff = Date(timeIntervalSince1970: 500)

        let first = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            scope: .allHistory,
            at: cutoff
        )
        let second = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            scope: .allHistory,
            at: cutoff
        )

        XCTAssertEqual(second, first)
    }

    func testExportContentCacheMaterializesEachContentOnlyOncePerCycle() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        try replica.clipboard.upsert(textItem(id: UUID(), text: "cached text"))
        let imageData = Self.pngData()
        let image = ClipboardItem(
            id: UUID(),
            kind: .imageData,
            displayTitle: "cached image",
            searchableText: "cached image",
            text: nil,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "Tests",
            contentHash: ClipboardContentHasher.sha256String(for: imageData),
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        try replica.clipboard.upsertPNG(image, data: imageData)
        var cache = SyncExportContentCache()
        let cutoff = Date(timeIntervalSince1970: 500)

        let first = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            scope: .allHistory,
            contentCache: &cache,
            at: cutoff
        )
        let second = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            scope: .allHistory,
            contentCache: &cache,
            at: cutoff
        )

        XCTAssertEqual(second, first)
        XCTAssertEqual(cache.materializedContentCount, 2)
    }

    func testFilteredExportBundleOnlyRemovesExcludedContent() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let kept = textItem(id: UUID(), text: "kept")
        let excluded = textItem(id: UUID(), text: "excluded")
        try replica.clipboard.upsert(kept)
        try replica.clipboard.upsert(excluded)
        let bundle = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            scope: .allHistory,
            at: Date(timeIntervalSince1970: 500)
        )

        let filtered = bundle.excludingContentIDs([try XCTUnwrap(excluded.contentHash)])

        XCTAssertEqual(filtered.clipboard.records.map(\.recordName), [kept.id.uuidString])
        XCTAssertEqual(filtered.contents.map(\.contentID), [try XCTUnwrap(kept.contentHash)])
        XCTAssertEqual(filtered.preferences, bundle.preferences)
        XCTAssertEqual(filtered.tombstones, bundle.tombstones)
        XCTAssertEqual(filtered.outboxCutoff, bundle.outboxCutoff)
        XCTAssertEqual(
            filtered.unavailableClipboardRecordNames,
            bundle.unavailableClipboardRecordNames
        )
    }

    func testFavoriteTagsRoundTripThroughSyncBundle() throws {
        let source = try makeReplica(deviceID: "device-a")
        let target = try makeReplica(deviceID: "device-b")
        defer {
            try? FileManager.default.removeItem(at: source.workingDirectory)
            try? FileManager.default.removeItem(at: target.workingDirectory)
        }
        let item = textItem(id: UUID(), text: "tagged sync item")
        try source.clipboard.upsert(item)
        try source.clipboard.setFavorite(id: item.id, isFavorite: true)
        try source.clipboard.setTags(id: item.id, tags: ["Work", "代码"])

        let bundle = try source.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 1,
            scope: .allHistory,
            at: Date(timeIntervalSince1970: 500)
        )
        let record = try XCTUnwrap(bundle.clipboard.records.first)
        XCTAssertEqual(record.tags, ["Work", "代码"])
        XCTAssertEqual(record.tagsClock.counter, 1)

        let contents = Dictionary(
            uniqueKeysWithValues: bundle.contents.map {
                ($0.contentID, $0.data)
            }
        )
        try target.sync.apply(
            clipboard: bundle.clipboard,
            contents: contents,
            payloadStore: target.payloadStore,
            historyLimit: 500
        )

        let imported = try XCTUnwrap(target.clipboard.item(id: item.id))
        XCTAssertEqual(imported.tags, ["Work", "代码"])
        XCTAssertEqual(imported.tagsClock, record.tagsClock)
    }

    func testExcludedClipboardContentStaysPendingWhenOtherRecordsAreAcknowledged() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let uploaded = textItem(id: UUID(), text: "uploaded")
        let blocked = textItem(id: UUID(), text: "blocked")
        try replica.clipboard.upsert(uploaded)
        try replica.clipboard.upsert(blocked)
        let blockedContentID = try XCTUnwrap(blocked.contentHash)
        let cutoff = Date().addingTimeInterval(1)

        let bundle = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 1,
            scope: .allHistory,
            excludingContentIDs: [blockedContentID],
            at: cutoff
        )

        XCTAssertEqual(bundle.clipboard.records.map(\.recordName), [uploaded.id.uuidString])
        XCTAssertEqual(bundle.contents.map(\.contentID), [try XCTUnwrap(uploaded.contentHash)])
        try replica.sync.acknowledgeSnapshot(
            upTo: bundle.outboxCutoff,
            excludingClipboardRecordNames: [blocked.id.uuidString],
            uploadedContentIDs: Set(bundle.contents.map(\.contentID))
        )
        XCTAssertTrue(try replica.sync.hasPendingChanges())
        XCTAssertFalse(try replica.sync.hasPendingChanges(
            excludingClipboardRecordNames: [blocked.id.uuidString]
        ))
    }

    func testPublishedSnapshotAcknowledgementCommitsLedgerOutboxAndProgressTogether() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let storeID = UUID()
        try replica.sync.bindStore(storeID)
        try replica.clipboard.upsert(textItem(id: UUID(), text: "published"))
        let cutoff = Date().addingTimeInterval(1)
        let identity = SyncSnapshotPublicationIdentity(
            storeID: storeID,
            deviceID: "device-a",
            generation: 1,
            revision: 7,
            snapshotDirectory: "g1-r7-digest"
        )
        try replica.sync.snapshotPublicationLedger.recordPrepared(
            SyncSnapshotPublicationRecord(
                storeID: storeID,
                deviceID: "device-a",
                generation: 1,
                revision: 7,
                snapshotDirectory: identity.snapshotDirectory,
                snapshotDigests: SyncSnapshotDigests(
                    clipboard: "clipboard",
                    preferences: "preferences",
                    tombstones: "tombstones"
                ),
                manifestDigest: "manifest",
                state: .prepared,
                supersededByRevision: nil,
                updatedAt: cutoff
            )
        )
        try replica.sync.snapshotPublicationLedger.markPublicationUncertain(identity)

        try replica.sync.acknowledgePublishedSnapshot(
            upTo: cutoff,
            excludingClipboardRecordNames: [],
            uploadedContentIDs: [],
            publicationIdentity: identity,
            manifestDigest: "manifest",
            revision: 7,
            seenRevisions: ["device-a": 7],
            at: cutoff
        )

        XCTAssertFalse(try replica.sync.hasPendingChanges())
        XCTAssertEqual(
            try replica.sync.snapshotPublicationLedger.record(for: identity)?.state,
            .published
        )
        XCTAssertEqual(try replica.overrides.replicaRevision(), 7)
        XCTAssertEqual(try replica.overrides.seenRevisions(), ["device-a": 7])
    }

    func testPublishedSnapshotAcknowledgementRollsBackWhenLedgerRecordIsMissing() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let storeID = UUID()
        try replica.sync.bindStore(storeID)
        try replica.clipboard.upsert(textItem(id: UUID(), text: "must stay pending"))

        XCTAssertThrowsError(
            try replica.sync.acknowledgePublishedSnapshot(
                upTo: Date().addingTimeInterval(1),
                excludingClipboardRecordNames: [],
                uploadedContentIDs: [],
                publicationIdentity: SyncSnapshotPublicationIdentity(
                    storeID: storeID,
                    deviceID: "device-a",
                    generation: 1,
                    revision: 1,
                    snapshotDirectory: "missing"
                ),
                manifestDigest: "missing",
                revision: 1,
                seenRevisions: ["device-a": 1]
            )
        ) { error in
            XCTAssertEqual(
                error as? SyncSnapshotPublicationLedgerError,
                .missingRecord
            )
        }

        XCTAssertTrue(try replica.sync.hasPendingChanges())
        XCTAssertEqual(try replica.overrides.replicaRevision(), 0)
        XCTAssertTrue(try replica.overrides.seenRevisions().isEmpty)
    }

    func testReplicaReceiptsReplaceOnlyTheirDeviceAndResetWithGeneration() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let storeID = UUID()
        try replica.sync.bindStore(storeID)
        let firstAppliedAt = Date(timeIntervalSince1970: 100)
        let replacementAppliedAt = Date(timeIntervalSince1970: 200)
        let peerReceipt = SyncReplicaReceipt(
            deviceID: "device-b",
            generation: 1,
            revision: 4,
            manifestDigest: "digest-b",
            appliedAt: firstAppliedAt
        )
        try replica.sync.recordReceipt(
            SyncReplicaReceipt(
                deviceID: "device-a",
                generation: 1,
                revision: 1,
                manifestDigest: "digest-a-1",
                appliedAt: firstAppliedAt
            )
        )
        try replica.sync.recordReceipt(peerReceipt)

        let replacement = SyncReplicaReceipt(
            deviceID: "device-a",
            generation: 1,
            revision: 2,
            manifestDigest: "digest-a-2",
            appliedAt: replacementAppliedAt
        )
        try replica.sync.recordReceipt(replacement)

        XCTAssertEqual(try replica.sync.receipts(), [replacement, peerReceipt])
        XCTAssertTrue(try replica.sync.adoptGeneration(2, storeID: storeID))
        XCTAssertTrue(try replica.sync.receipts().isEmpty)
    }

    func testReceiptMatchesOnlyExactReplicaIdentity() {
        let receipt = SyncReplicaReceipt(
            deviceID: "device-a",
            generation: 2,
            revision: 7,
            manifestDigest: "digest-a",
            appliedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(receipt.matches(
            deviceID: "device-a",
            generation: 2,
            revision: 7,
            manifestDigest: "digest-a"
        ))
        XCTAssertFalse(receipt.matches(
            deviceID: "device-b",
            generation: 2,
            revision: 7,
            manifestDigest: "digest-a"
        ))
        XCTAssertFalse(receipt.matches(
            deviceID: "device-a",
            generation: 3,
            revision: 7,
            manifestDigest: "digest-a"
        ))
        XCTAssertFalse(receipt.matches(
            deviceID: "device-a",
            generation: 2,
            revision: 8,
            manifestDigest: "digest-a"
        ))
        XCTAssertFalse(receipt.matches(
            deviceID: "device-a",
            generation: 2,
            revision: 7,
            manifestDigest: "digest-b"
        ))
    }

    func testTombstoneCompactsOnlyAfterEveryVisibleDeviceAcknowledgesSourceRevision() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let item = textItem(id: UUID(), text: "to delete")
        try replica.clipboard.upsert(item)
        try replica.clipboard.delete(id: item.id)
        let initial = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            scope: .allHistory
        )
        XCTAssertEqual(initial.tombstones.records.count, 1)

        let digest = SyncSnapshotDigests(clipboard: "c", preferences: "p", tombstones: "t")
        let sourceManifest = SyncReplicaManifest(
            deviceID: "device-a",
            generation: 1,
            revision: 3,
            seenRevisions: ["device-a": 3],
            snapshotDigests: digest,
            updatedAt: Date()
        )
        let stalePeer = SyncReplicaManifest(
            deviceID: "device-b",
            generation: 1,
            revision: 5,
            seenRevisions: ["device-a": 2],
            snapshotDigests: digest,
            updatedAt: Date()
        )
        XCTAssertTrue(try replica.sync.compactAcknowledgedTombstones(
            activeManifests: [sourceManifest, stalePeer],
            localDeviceID: "device-a",
            generation: 1
        ).isEmpty)

        var acknowledgingPeer = stalePeer
        acknowledgingPeer.seenRevisions["device-a"] = 3
        XCTAssertEqual(try replica.sync.compactAcknowledgedTombstones(
            activeManifests: [sourceManifest, acknowledgingPeer],
            localDeviceID: "device-a",
            generation: 1
        ).count, 1)
        XCTAssertTrue(try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 4,
            scope: .allHistory
        ).tombstones.records.isEmpty)
    }

    func testCapacityBlockedClipboardRecordRemainsPendingWhileOtherChangesAreAcknowledged() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let uploaded = textItem(id: UUID(), text: "uploaded")
        let blocked = textItem(id: UUID(), text: "blocked")
        try replica.clipboard.upsert(uploaded)
        try replica.clipboard.upsert(blocked)

        let cutoff = Date().addingTimeInterval(1)
        try replica.sync.acknowledgeSnapshot(
            upTo: cutoff,
            excludingClipboardRecordNames: [blocked.id.uuidString]
        )

        XCTAssertTrue(try replica.sync.hasPendingChanges())
        XCTAssertFalse(try replica.sync.hasPendingChanges(
            excludingClipboardRecordNames: [blocked.id.uuidString]
        ))
    }

    func testMissingLocalImagePayloadStaysPendingWithoutBlockingOtherChanges() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let imageID = UUID()
        let imageData = Self.pngData()
        let image = ClipboardItem(
            id: imageID,
            kind: .imageData,
            displayTitle: "image",
            searchableText: "image",
            text: nil,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "Tests",
            contentHash: ClipboardContentHasher.sha256String(for: imageData),
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        try replica.clipboard.upsertPNG(image, data: imageData)
        let text = textItem(id: UUID(), text: "available")
        try replica.clipboard.upsert(text)
        let savedImage = try XCTUnwrap(
            replica.clipboard.search("", limit: 10).first { $0.id == imageID }
        )
        try FileManager.default.removeItem(
            atPath: try XCTUnwrap(savedImage.cachedFilePath)
        )

        let bundle = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 1,
            scope: .allHistory
        )

        XCTAssertEqual(bundle.clipboard.records.map(\.recordName), [text.id.uuidString])
        XCTAssertEqual(bundle.unavailableClipboardRecordNames, [imageID.uuidString])
        try replica.sync.acknowledgeSnapshot(
            upTo: bundle.outboxCutoff,
            excludingClipboardRecordNames: bundle.unavailableClipboardRecordNames
        )
        XCTAssertTrue(try replica.sync.hasPendingChanges())
        XCTAssertFalse(try replica.sync.hasPendingChanges(
            excludingClipboardRecordNames: [imageID.uuidString]
        ))
    }

    func testAdoptingNewGenerationRemovesOlderTombstones() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let storeID = UUID()
        try replica.sync.bindStore(storeID)
        let item = textItem(id: UUID(), text: "old generation")
        try replica.clipboard.upsert(item)
        try replica.clipboard.delete(id: item.id)
        XCTAssertEqual(
            try replica.sync.tombstonedRecordNames(generation: 1),
            [item.id.uuidString]
        )

        XCTAssertTrue(try replica.sync.adoptGeneration(2, storeID: storeID))

        XCTAssertTrue(try replica.sync.tombstonedRecordNames(generation: 1).isEmpty)
    }

    func testStaleReplicaCannotRestoreTombstonedClipboardRecord() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let item = textItem(id: UUID(), text: "deleted remotely")
        let tombstone = SyncTombstoneSnapshot(
            deviceID: "device-a",
            generation: 1,
            revision: 2,
            records: [
                SyncTombstoneRecord(
                    tombstoneID: "tombstone.1.\(item.id.uuidString)",
                    targetRecordName: item.id.uuidString,
                    targetType: "ClipboardContent",
                    generation: 1,
                    deletedAt: Date(timeIntervalSince1970: 200),
                    reason: "user",
                    sourceDeviceID: "device-a",
                    sourceRevision: 2
                )
            ]
        )
        let staleSnapshot = SyncClipboardSnapshot(
            deviceID: "device-b",
            generation: 1,
            revision: 1,
            records: [
                SyncClipboardRecord(
                    recordName: item.id.uuidString,
                    contentID: try XCTUnwrap(item.contentHash),
                    kind: .text,
                    displayTitle: item.displayTitle,
                    searchableText: item.searchableText,
                    sourceApp: item.sourceApp,
                    createdAt: item.createdAt,
                    lastCapturedAt: item.lastCapturedAt,
                    lastUsedAt: item.lastUsedAt,
                    retentionAt: item.retentionAt,
                    useCount: item.useCount,
                    isPinned: item.isPinned,
                    isFavorite: item.isFavorite,
                    favoriteClock: item.favoriteClock,
                    pinnedClock: item.pinnedClock
                )
            ]
        )
        let contentID = try XCTUnwrap(item.contentHash)
        let object = SyncTextContentObject(
            contentID: contentID,
            kind: .text,
            text: try XCTUnwrap(item.text),
            byteCount: Int64(item.text?.utf8.count ?? 0)
        )

        try replica.sync.apply(tombstones: tombstone)
        try replica.sync.apply(
            clipboard: staleSnapshot,
            contents: [contentID: try SyncSnapshotCodec.encode(object)],
            payloadStore: replica.payloadStore,
            historyLimit: 500
        )

        XCTAssertTrue(try replica.clipboard.search("", limit: 500).isEmpty)
    }

    func testRemovingPeerRehomesItsUncompactedTombstone() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let targetID = UUID()
        let tombstone = SyncTombstoneSnapshot(
            deviceID: "device-b",
            generation: 1,
            revision: 4,
            records: [
                SyncTombstoneRecord(
                    tombstoneID: "tombstone.1.\(targetID.uuidString)",
                    targetRecordName: targetID.uuidString,
                    targetType: "ClipboardContent",
                    generation: 1,
                    deletedAt: Date(timeIntervalSince1970: 200),
                    reason: "user",
                    sourceDeviceID: "device-b",
                    sourceRevision: 4
                )
            ]
        )
        try replica.sync.apply(tombstones: tombstone)
        XCTAssertTrue(try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 1,
            scope: .allHistory
        ).tombstones.records.isEmpty)

        try replica.sync.preserveTombstones(
            fromRemovedDeviceID: "device-b",
            generation: 1,
            at: Date(timeIntervalSince1970: 300)
        )
        let rehomed = try replica.sync.exportBundle(
            deviceID: "device-a",
            generation: 1,
            revision: 2,
            scope: .allHistory
        )

        XCTAssertTrue(try replica.sync.hasPendingChanges())
        XCTAssertEqual(rehomed.tombstones.records.count, 1)
        XCTAssertEqual(rehomed.tombstones.records[0].sourceDeviceID, "device-a")
        XCTAssertEqual(rehomed.tombstones.records[0].sourceRevision, 2)
    }

    func testImportedPeerTombstoneCompactsAfterEveryDeviceAcknowledgesItsSourceRevision() throws {
        let replica = try makeReplica(deviceID: "device-a")
        defer { try? FileManager.default.removeItem(at: replica.workingDirectory) }
        let targetID = UUID()
        try replica.sync.apply(tombstones: SyncTombstoneSnapshot(
            deviceID: "device-b",
            generation: 1,
            revision: 4,
            records: [
                SyncTombstoneRecord(
                    tombstoneID: "tombstone.1.\(targetID.uuidString)",
                    targetRecordName: targetID.uuidString,
                    targetType: "ClipboardContent",
                    generation: 1,
                    deletedAt: Date(timeIntervalSince1970: 200),
                    reason: "user",
                    sourceDeviceID: "device-b",
                    sourceRevision: 4
                )
            ]
        ))
        let digests = SyncSnapshotDigests(clipboard: "c", preferences: "p", tombstones: "t")
        let localManifest = SyncReplicaManifest(
            deviceID: "device-a",
            generation: 1,
            revision: 2,
            seenRevisions: ["device-b": 4],
            snapshotDigests: digests,
            updatedAt: Date()
        )
        let sourceManifest = SyncReplicaManifest(
            deviceID: "device-b",
            generation: 1,
            revision: 5,
            seenRevisions: ["device-b": 5],
            snapshotDigests: digests,
            updatedAt: Date()
        )

        let compacted = try replica.sync.compactAcknowledgedTombstones(
            activeManifests: [localManifest, sourceManifest],
            localDeviceID: "device-a",
            generation: 1
        )

        XCTAssertEqual(compacted.count, 1)
        XCTAssertTrue(try replica.sync.tombstonedRecordNames(generation: 1).isEmpty)
    }

    private struct Replica {
        var clipboard: ClipboardRepository
        var preferences: PreferenceRepository
        var sync: SyncLocalRepository
        var overrides: DeviceOverrideRepository
        var payloadStore: PayloadStore
        var workingDirectory: URL
    }

    private func makeReplica(deviceID: String) throws -> Replica {
        let database = try MacToolsDatabase.inMemory()
        let workingDirectory = temporaryDirectory()
        let payloadStore = PayloadStore(
            rootDirectory: workingDirectory.appendingPathComponent("Payloads", isDirectory: true)
        )
        let clipboard = ClipboardRepository(database: database, payloadStore: payloadStore)
        let preferences = PreferenceRepository(database: database)
        try preferences.save(.defaults, enqueuesSyncChange: false)
        let overrides = DeviceOverrideRepository(database: database)
        _ = try overrides.deviceID()
        return Replica(
            clipboard: clipboard,
            preferences: preferences,
            sync: SyncLocalRepository(
                database: database,
                clipboardRepository: clipboard,
                preferenceRepository: preferences
            ),
            overrides: overrides,
            payloadStore: payloadStore,
            workingDirectory: workingDirectory
        )
    }

    private func textItem(id: UUID, text: String) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .text,
            displayTitle: text,
            searchableText: text,
            text: text,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "Tests",
            contentHash: ClipboardContentHasher.sha256String(for: Data("text:\(text)".utf8)),
            createdAt: Date(timeIntervalSince1970: 100),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func pngData() -> Data {
        Data(base64Encoded: onePixelPNGBase64)!
    }

    private static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
