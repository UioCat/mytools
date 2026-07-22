import Foundation
import XCTest
@testable import MacToolsCore

final class DriveSyncStoreTests: XCTestCase {
    func testPrepareCreatesExpectedRootAndStableProtocol() throws {
        try withStore { store, root in
            let now = Date(timeIntervalSince1970: 1_000)
            let first = try store.prepare(initialCapacity: .megabytes512, now: now)
            let second = try store.prepare(initialCapacity: .gigabytes2, now: now.addingTimeInterval(1))

            XCTAssertEqual(first, second)
            XCTAssertEqual(first.capacityLimit, .megabytes512)
            for path in [
                "protocol.json", ".mactools-keep", "objects/text/sha256",
                "objects/images/sha256", "replicas", "evictions", "resets",
                "removed-devices"
            ] {
                XCTAssertTrue(FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ), path)
            }
        }
    }

    func testReadProtocolDoesNotRecreateMissingSyncRoot() throws {
        try withStore { store, root in
            XCTAssertThrowsError(try store.readProtocol()) { error in
                XCTAssertEqual(error as? DriveSyncStoreError, .missingProtocol)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testWritesContentSnapshotsAndManifestThenReadsVerifiedReplica() throws {
        try withStore { store, root in
            _ = try store.prepare()
            let bundle = try makeBundle(deviceID: "device-a", revision: 3, text: "hello")

            let manifest = try store.write(
                bundle,
                seenRevisions: ["device-b": 2],
                updatedAt: Date(timeIntervalSince1970: 10)
            )
            let replicas = try store.replicas(generation: 1)

            XCTAssertEqual(replicas.count, 1)
            XCTAssertEqual(replicas[0].manifest, manifest)
            XCTAssertEqual(replicas[0].clipboard, bundle.clipboard)
            XCTAssertEqual(replicas[0].preferences, bundle.preferences)
            XCTAssertEqual(replicas[0].tombstones, bundle.tombstones)
            let contentID = try XCTUnwrap(bundle.contents.first?.contentID)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("objects/text/sha256")
                    .appendingPathComponent(String(contentID.prefix(2)))
                    .appendingPathComponent(contentID)
                    .appendingPathExtension("json").path
            ))
        }
    }

    func testDigestMismatchIsolatesReplicaAndKeepsHealthyPeer() throws {
        try withStore { store, root in
            _ = try store.prepare()
            let bundle = try makeBundle(deviceID: "device-a", revision: 1, text: "hello")
            let manifest = try store.write(bundle, seenRevisions: [:], updatedAt: Date())
            _ = try store.write(
                makeBundle(deviceID: "device-b", revision: 1, text: "healthy"),
                seenRevisions: [:],
                updatedAt: Date()
            )
            let snapshotDirectory = try XCTUnwrap(manifest.snapshotDirectory)
            try Data("{}".utf8).write(
                to: root.appendingPathComponent(
                    "replicas/device-a/revisions/\(snapshotDirectory)/clipboard.json"
                ),
                options: [.atomic]
            )

            let scan = try store.scanReplicas(generation: 1)

            XCTAssertEqual(scan.replicas.map(\.manifest.deviceID), ["device-b"])
            XCTAssertEqual(scan.failures, [
                DriveSyncReplicaFailure(
                    deviceID: "device-a",
                    error: .snapshotDigestMismatch(
                        deviceID: "device-a",
                        fileName: "clipboard.json"
                    )
                )
            ])
            XCTAssertEqual(try store.replicas(generation: 1).map(\.manifest.deviceID), ["device-b"])
        }
    }

    func testInterruptedUncommittedRevisionCannotInvalidateCommittedReplica() throws {
        try withStore { store, root in
            _ = try store.prepare()
            let first = try makeBundle(deviceID: "device-a", revision: 1, text: "committed")
            let firstManifest = try store.write(first, seenRevisions: [:], updatedAt: Date())
            let orphanDirectory = root.appendingPathComponent(
                "replicas/device-a/revisions/g1-r2-orphan",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
            try Data("partial".utf8).write(
                to: orphanDirectory.appendingPathComponent("clipboard.json")
            )

            let beforeRepair = try XCTUnwrap(store.replicas(generation: 1).first)
            XCTAssertEqual(beforeRepair.manifest, firstManifest)
            XCTAssertEqual(beforeRepair.clipboard, first.clipboard)

            let second = try makeBundle(deviceID: "device-a", revision: 2, text: "next")
            let secondManifest = try store.write(second, seenRevisions: [:], updatedAt: Date())
            let revisionEntries = try FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent("replicas/device-a/revisions").path
            )

            XCTAssertFalse(revisionEntries.contains("g1-r2-orphan"))
            XCTAssertTrue(revisionEntries.contains(try XCTUnwrap(firstManifest.snapshotDirectory)))
            XCTAssertTrue(revisionEntries.contains(try XCTUnwrap(secondManifest.snapshotDirectory)))
            XCTAssertEqual(try store.replicas(generation: 1).first?.clipboard, second.clipboard)
        }
    }

    func testSameContentFromSecondDeviceKeepsSingleObject() throws {
        try withStore { store, root in
            _ = try store.prepare()
            _ = try store.write(
                makeBundle(deviceID: "device-a", revision: 1, text: "same"),
                seenRevisions: [:],
                updatedAt: Date()
            )
            _ = try store.write(
                makeBundle(deviceID: "device-b", revision: 1, text: "same"),
                seenRevisions: ["device-a": 1],
                updatedAt: Date()
            )

            let objectRoot = root.appendingPathComponent("objects/text/sha256")
            let files = FileManager.default.enumerator(atPath: objectRoot.path)?.allObjects
                .compactMap { $0 as? String }
                .filter { $0.hasSuffix(".json") }
            XCTAssertEqual(files?.count, 1)
            XCTAssertEqual(try store.replicas(generation: 1).count, 2)
        }
    }

    func testStoredObjectBytesMatchTextUsageCategory() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            _ = try store.write(
                makeBundle(deviceID: "device-a", revision: 1, text: "usage"),
                seenRevisions: [:],
                updatedAt: Date(timeIntervalSince1970: 100)
            )

            let objects = try store.storedObjects()
            let usage = try store.usage(
                capacityBytes: SyncStorageLimit.megabytes512.byteLimit,
                ordinaryHistoryCount: 1
            )
            let inventory = try store.storageInventory()

            XCTAssertEqual(objects.count, 1)
            XCTAssertEqual(inventory.objects, objects)
            XCTAssertEqual(
                inventory.usage(
                    capacityBytes: SyncStorageLimit.megabytes512.byteLimit,
                    ordinaryHistoryCount: 1
                ),
                usage
            )
            XCTAssertEqual(usage.textBytes, objects[0].byteCount)
            XCTAssertEqual(usage.imageBytes, 0)
            XCTAssertGreaterThan(usage.metadataBytes, 0)
            XCTAssertEqual(
                usage.usedBytes,
                usage.textBytes + usage.imageBytes + usage.metadataBytes
            )
            XCTAssertEqual(usage.ordinaryHistoryCount, 1)
        }
    }

    func testStorageInventoryCanAccountForGarbageRemovalWithoutRescanning() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            _ = try store.write(
                makeBundle(deviceID: "device-a", revision: 1, text: "garbage"),
                seenRevisions: [:],
                updatedAt: Date(timeIntervalSince1970: 100)
            )
            let inventory = try store.storageInventory()
            let contentID = try XCTUnwrap(inventory.objects.first?.contentID)

            let updated = inventory.removingObjects(withContentIDs: [contentID])

            XCTAssertTrue(updated.objects.isEmpty)
            XCTAssertEqual(updated.textBytes, 0)
            XCTAssertEqual(updated.imageBytes, inventory.imageBytes)
            XCTAssertEqual(updated.metadataBytes, inventory.metadataBytes)
        }
    }

    func testValidLocalContentRepairsCorruptedSharedObject() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            let first = try makeBundle(deviceID: "device-a", revision: 1, text: "same")
            let content = try XCTUnwrap(first.contents.first)
            _ = try store.write(first, seenRevisions: [:], updatedAt: Date())

            let objectURL = try store.contentFileURL(
                contentID: content.contentID,
                kind: content.kind
            )
            try Data("corrupt".utf8).write(to: objectURL, options: [.atomic])
            XCTAssertThrowsError(
                try store.contentData(contentID: content.contentID, kind: content.kind)
            ) { error in
                XCTAssertEqual(
                    error as? DriveSyncStoreError,
                    .contentHashMismatch(content.contentID)
                )
            }

            let second = try makeBundle(deviceID: "device-b", revision: 1, text: "same")
            _ = try store.write(second, seenRevisions: ["device-a": 1], updatedAt: Date())

            XCTAssertEqual(
                try store.contentData(contentID: content.contentID, kind: content.kind),
                content.data
            )
            XCTAssertEqual(try store.replicas(generation: 1).count, 2)
        }
    }

    func testHashCorrectNonPNGSharedObjectIsRejectedBeforeApply() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            let invalidImage = Data("not a png".utf8)
            let contentID = ClipboardContentHasher.sha256String(for: invalidImage)
            let objectURL = try store.contentFileURL(contentID: contentID, kind: .imageData)
            try FileManager.default.createDirectory(
                at: objectURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try invalidImage.write(to: objectURL, options: [.atomic])

            XCTAssertThrowsError(
                try store.contentData(contentID: contentID, kind: .imageData)
            ) { error in
                XCTAssertEqual(
                    error as? DriveSyncStoreError,
                    .contentHashMismatch(contentID)
                )
            }
        }
    }

    func testUnreferencedObjectNeedsStableWindowBeforeRemoval() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            _ = try store.write(
                makeBundle(deviceID: "device-a", revision: 1, text: "garbage"),
                seenRevisions: [:],
                updatedAt: Date()
            )
            let object = try XCTUnwrap(store.storedObjects().first)
            let database = try MacToolsDatabase.inMemory()
            let payloadStore = PayloadStore(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
            )
            let clipboard = ClipboardRepository(database: database, payloadStore: payloadStore)
            let local = SyncLocalRepository(
                database: database,
                clipboardRepository: clipboard,
                preferenceRepository: PreferenceRepository(database: database)
            )
            let observedAt = Date(timeIntervalSince1970: 1_000)

            XCTAssertTrue(try local.garbageCollectionCandidates(
                allContentIDs: [object.contentID],
                referencedContentIDs: [],
                now: observedAt
            ).isEmpty)
            XCTAssertTrue(try local.garbageCollectionCandidates(
                allContentIDs: [object.contentID],
                referencedContentIDs: [],
                now: observedAt.addingTimeInterval(24 * 60 * 60 - 1)
            ).isEmpty)
            let eligible = try local.garbageCollectionCandidates(
                allContentIDs: [object.contentID],
                referencedContentIDs: [],
                now: observedAt.addingTimeInterval(24 * 60 * 60)
            )
            XCTAssertEqual(eligible, [object.contentID])

            try store.removeObject(object)
            try local.acknowledgeGarbageCollected(contentIDs: eligible)
            XCTAssertTrue(try store.storedObjects().isEmpty)
        }
    }

    func testEvictionSnapshotPreservesEffectiveRecordsUntilExplicitlyReplaced() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            let eviction = SyncEvictionRecord(
                contentID: String(repeating: "a", count: 64),
                reason: .capacityLimit,
                deviceID: "device-a",
                generation: 1,
                observedRetentionAt: Date(timeIntervalSince1970: 100),
                observedFavoriteClock: .zero,
                observedPinnedClock: .zero,
                evictedAt: Date(timeIntervalSince1970: 200)
            )
            let snapshot = SyncEvictionSnapshot(
                deviceID: "device-a",
                generation: 1,
                records: [eviction]
            )

            try store.writeEvictions(snapshot)

            XCTAssertEqual(try store.evictionSnapshot(deviceID: "device-a"), snapshot)
            XCTAssertEqual(try store.evictions(generation: 1), [eviction])
        }
    }

    func testRemovedDeviceMarkersRemainEffectiveInLaterGenerations() throws {
        try withStore { store, _ in
            _ = try store.prepare()
            try store.writeRemovedDevice(
                SyncRemovedDeviceMarker(
                    removedDeviceID: "device-b",
                    removerDeviceID: "device-a",
                    generation: 2,
                    removedAt: Date(timeIntervalSince1970: 100)
                )
            )

            XCTAssertTrue(try store.removedDeviceIDs(generation: 1).isEmpty)
            XCTAssertEqual(try store.removedDeviceIDs(generation: 2), ["device-b"])
            XCTAssertEqual(try store.removedDeviceIDs(generation: 3), ["device-b"])
        }
    }

    func testUnsupportedSnapshotSchemaIsIsolated() throws {
        try withStore { store, root in
            _ = try store.prepare()
            let bundle = try makeBundle(deviceID: "device-a", revision: 1, text: "hello")
            let manifest = try store.write(bundle, seenRevisions: [:], updatedAt: Date())
            var clipboard = bundle.clipboard
            clipboard.schemaVersion = 999
            let clipboardData = try SyncSnapshotCodec.encode(clipboard)
            var rewrittenManifest = manifest
            rewrittenManifest.snapshotDigests.clipboard = SyncSnapshotCodec.digest(clipboardData)
            let revisionDirectory = root.appendingPathComponent(
                "replicas/device-a/revisions/\(try XCTUnwrap(manifest.snapshotDirectory))"
            )
            try clipboardData.write(
                to: revisionDirectory.appendingPathComponent("clipboard.json"),
                options: [.atomic]
            )
            try SyncSnapshotCodec.encode(rewrittenManifest).write(
                to: root.appendingPathComponent("replicas/device-a/manifest.json"),
                options: [.atomic]
            )

            let scan = try store.scanReplicas(generation: 1)

            XCTAssertTrue(scan.replicas.isEmpty)
            XCTAssertEqual(
                scan.failures.first?.error,
                .incompatibleSchema(fileName: "clipboard.json", found: 999)
            )
        }
    }

    private func makeBundle(deviceID: String, revision: Int64, text: String) throws -> SyncExportBundle {
        let contentID = ClipboardContentHasher.sha256String(for: Data("text:\(text)".utf8))
        let content = SyncTextContentObject(
            contentID: contentID,
            kind: .text,
            text: text,
            byteCount: Int64(Data(text.utf8).count)
        )
        let date = Date(timeIntervalSince1970: 100)
        return SyncExportBundle(
            clipboard: SyncClipboardSnapshot(
                deviceID: deviceID,
                generation: 1,
                revision: revision,
                records: [
                    SyncClipboardRecord(
                        recordName: UUID().uuidString,
                        contentID: contentID,
                        kind: .text,
                        displayTitle: text,
                        searchableText: text,
                        sourceApp: nil,
                        createdAt: date,
                        lastCapturedAt: date,
                        lastUsedAt: nil,
                        retentionAt: date,
                        useCount: 0,
                        isPinned: false,
                        isFavorite: false,
                        favoriteClock: .zero,
                        pinnedClock: .zero
                    )
                ]
            ),
            preferences: SyncPreferencesSnapshot(
                deviceID: deviceID,
                generation: 1,
                revision: revision,
                domains: []
            ),
            tombstones: SyncTombstoneSnapshot(
                deviceID: deviceID,
                generation: 1,
                revision: revision,
                records: []
            ),
            contents: [
                SyncExportContent(
                    contentID: contentID,
                    kind: .text,
                    data: try SyncSnapshotCodec.encode(content)
                )
            ],
            outboxCutoff: date
        )
    }

    private func withStore(_ body: (DriveSyncStore, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(DriveSyncStore.rootDirectoryName, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try body(DriveSyncStore(rootURL: root), root)
    }
}
