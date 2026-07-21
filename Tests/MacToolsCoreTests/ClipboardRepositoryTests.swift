import XCTest
@testable import MacToolsCore

final class ClipboardRepositoryTests: XCTestCase {
    func testUpsertAndSearchByTitleOrSearchableText() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let item = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Swift notes",
            searchableText: "AppKit pasteboard history",
            text: "AppKit pasteboard history",
            sourceApp: "Notes",
            createdAt: Date(timeIntervalSince1970: 100),
            isFavorite: true
        )

        try repository.upsert(item)

        let titleResults = try repository.search("swift", limit: 20)
        XCTAssertEqual(titleResults, [item])

        let searchableResults = try repository.search("pasteboard", limit: 20)
        XCTAssertEqual(searchableResults, [item])
    }

    func testSearchReturnsPinnedItemsFirstThenNewestItems() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let olderPinned = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "older pinned",
            createdAt: Date(timeIntervalSince1970: 100),
            isPinned: true
        )
        let newerNormal = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "newer normal",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let olderNormal = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            title: "older normal",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        try repository.upsert(newerNormal)
        try repository.upsert(olderPinned)
        try repository.upsert(olderNormal)

        let results = try repository.search("", limit: 20)

        XCTAssertEqual(results.map(\.id), [olderPinned.id, newerNormal.id, olderNormal.id])
    }

    func testUpsertDeduplicatesByContentHash() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let first = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            title: "first",
            createdAt: Date(timeIntervalSince1970: 100),
            contentHash: "same-md5"
        )
        let second = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            title: "second",
            createdAt: Date(timeIntervalSince1970: 200),
            contentHash: "same-md5"
        )

        try repository.upsert(first)
        try repository.upsert(second)

        let results = try repository.search("", limit: 20)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, first.id)
        XCTAssertEqual(results[0].displayTitle, "second")
        XCTAssertEqual(results[0].contentHash, "same-md5")
    }

    func testRemoteDeduplicationAlwaysKeepsLexicographicallySmallestRecordName() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let larger = ClipboardItem.testItem(
            id: UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!,
            title: "larger",
            createdAt: Date(timeIntervalSince1970: 1),
            contentHash: "same-content"
        )
        let smaller = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "smaller",
            createdAt: Date(timeIntervalSince1970: 2),
            contentHash: "same-content"
        )

        try repository.upsert(larger)
        let result = try repository.upsert(
            smaller,
            enqueuesSyncChange: false,
            deterministicallyMergesRecordNames: true
        )

        XCTAssertEqual(result.itemID, smaller.id)
        XCTAssertEqual(result.duplicateRecordIDs, [larger.id])
        XCTAssertEqual(try repository.search("", limit: 10).map(\.id), [smaller.id])
    }

    func testFavoriteClockAllowsNewerRemoteUnfavoriteToWin() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        var item = ClipboardItem.testItem(
            id: id,
            title: "clocked",
            createdAt: Date(timeIntervalSince1970: 1),
            contentHash: "clocked"
        )
        try repository.upsert(item)
        try repository.setFavorite(id: id, isFavorite: true)

        item.isFavorite = false
        item.favoriteClock = ClipboardFieldClock(counter: 2, deviceID: "remote")
        try repository.upsert(item, enqueuesSyncChange: false)

        XCTAssertFalse(try XCTUnwrap(repository.item(id: id)).isFavorite)
    }

    func testEqualFavoriteClockConservativelyKeepsFavoriteRegardlessOfMergeOrder() throws {
        let clock = ClipboardFieldClock(counter: 1, deviceID: "migration-device")
        var unprotected = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            title: "clocked",
            createdAt: Date(timeIntervalSince1970: 1),
            contentHash: "equal-clock"
        )
        unprotected.favoriteClock = clock
        var protected = unprotected
        protected.id = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        protected.isFavorite = true

        let firstDatabase = try ClipboardDatabase.inMemory()
        let firstRepository = ClipboardRepository(database: firstDatabase)
        try firstRepository.upsert(unprotected, enqueuesSyncChange: false)
        try firstRepository.upsert(protected, enqueuesSyncChange: false)
        let secondDatabase = try ClipboardDatabase.inMemory()
        let secondRepository = ClipboardRepository(database: secondDatabase)
        try secondRepository.upsert(protected, enqueuesSyncChange: false)
        try secondRepository.upsert(unprotected, enqueuesSyncChange: false)

        XCTAssertTrue(try XCTUnwrap(firstRepository.search("", limit: 1).first).isFavorite)
        XCTAssertTrue(try XCTUnwrap(secondRepository.search("", limit: 1).first).isFavorite)
    }

    func testFavoritesCanBeFilteredAndToggled() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let item = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            title: "favorite me",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        try repository.upsert(item)
        XCTAssertTrue(try repository.search("", limit: 20, favoritesOnly: true).isEmpty)

        try repository.setFavorite(id: item.id, isFavorite: true)

        let favorites = try repository.search("", limit: 20, favoritesOnly: true)
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites[0].id, item.id)
        XCTAssertTrue(favorites[0].isFavorite)
    }

    func testDeleteRemovesClipboardItem() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let item = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            title: "delete me",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        try repository.upsert(item)
        try repository.delete(id: item.id)

        XCTAssertTrue(try repository.search("", limit: 20).isEmpty)
    }

    func testDeleteAllNonFavoritesKeepsFavoriteItems() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let normalItem = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            title: "remove me",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let favoriteItem = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            title: "keep me",
            createdAt: Date(timeIntervalSince1970: 200),
            isFavorite: true
        )

        try repository.upsert(normalItem)
        try repository.upsert(favoriteItem)
        try repository.deleteAllNonFavorites()

        let results = try repository.search("", limit: 20)
        XCTAssertEqual(results.map(\.id), [favoriteItem.id])
    }

    func testMarkUsedUpdatesLastUsedAtAndIncrementsUseCount() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let item = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            title: "Used item",
            createdAt: Date(timeIntervalSince1970: 100),
            useCount: 2
        )
        let usedAt = Date(timeIntervalSince1970: 500)

        try repository.upsert(item)
        try repository.markUsed(id: item.id, at: usedAt)

        let results = try repository.search("used", limit: 20)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].lastUsedAt, usedAt)
        XCTAssertEqual(results[0].useCount, 3)
    }

    func testOnDiskDatabaseCreatesParentDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("clipboard.sqlite")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: databaseURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: databaseURL.path
        )

        _ = try ClipboardDatabase.at(databaseURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.deletingLastPathComponent().path))
        XCTAssertEqual(try permissions(at: databaseURL.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(at: databaseURL), 0o600)
    }

    func testNewInsertPrunesOldestNormalItemByRetentionTime() throws {
        let database = try MacToolsDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let oldestByCaptureButRecentlyUsed = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            title: "recently used",
            createdAt: Date(timeIntervalSince1970: 10),
            lastUsedAt: Date(timeIntervalSince1970: 300),
            contentHash: "recently-used"
        )
        let oldestRetention = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            title: "old retention",
            createdAt: Date(timeIntervalSince1970: 20),
            contentHash: "old-retention"
        )
        let newest = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            title: "newest",
            createdAt: Date(timeIntervalSince1970: 400),
            contentHash: "newest"
        )

        try repository.upsert(oldestByCaptureButRecentlyUsed)
        try repository.upsert(oldestRetention)
        let result = try repository.upsert(newest, historyLimit: 2)

        XCTAssertTrue(result.inserted)
        XCTAssertEqual(result.prunedItemIDs, [oldestRetention.id])
        XCTAssertEqual(try repository.countNormalItems(), 2)
        XCTAssertEqual(Set(try repository.search("", limit: 10).map(\.id)), [oldestByCaptureButRecentlyUsed.id, newest.id])
    }

    func testPruningMigratedItemsDoesNotLeaveOrphanedSyncEvictions() throws {
        let database = try MacToolsDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let first = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000141")!,
            title: "migrated first",
            createdAt: Date(timeIntervalSince1970: 1),
            contentHash: "migrated-first"
        )
        let second = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000142")!,
            title: "migrated second",
            createdAt: Date(timeIntervalSince1970: 2),
            contentHash: "migrated-second"
        )
        try repository.upsert(first, historyLimit: 1, enqueuesSyncChange: false)
        try repository.upsert(second, historyLimit: 1, enqueuesSyncChange: false)

        let evictionCount = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_clipboard_evictions") ?? -1
        }
        XCTAssertEqual(evictionCount, 0)
    }

    func testStartupCleanupRemovesOnlyOrphanedLocalEvictions() throws {
        let database = try MacToolsDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO local_clipboard_evictions (recordName, kind, evictedAt)
                VALUES ('orphaned', 'text', ?), ('pending', 'text', ?)
                """,
                arguments: [Date(), Date()]
            )
            try db.execute(
                sql: """
                INSERT INTO sync_outbox (
                    recordType, recordName, operation, generation, createdAt, attemptCount
                ) VALUES (?, 'pending', 'save', 1, ?, 0)
                """,
                arguments: [SyncRecordType.clipboardContent.rawValue, Date()]
            )
        }

        XCTAssertEqual(try repository.cleanupOrphanedLocalEvictions(), 1)

        let recordNames = try database.writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT recordName FROM local_clipboard_evictions ORDER BY recordName"
            )
        }
        XCTAssertEqual(recordNames, ["pending"])
    }

    func testFavoritesAndPinnedItemsDoNotCountTowardHistoryLimit() throws {
        let database = try MacToolsDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let favorite = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            title: "favorite",
            createdAt: Date(timeIntervalSince1970: 1),
            isFavorite: true,
            contentHash: "favorite"
        )
        let pinned = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000112")!,
            title: "pinned",
            createdAt: Date(timeIntervalSince1970: 2),
            isPinned: true,
            contentHash: "pinned"
        )
        let normal = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000113")!,
            title: "normal",
            createdAt: Date(timeIntervalSince1970: 3),
            contentHash: "normal"
        )

        try repository.upsert(favorite, historyLimit: 1)
        try repository.upsert(pinned, historyLimit: 1)
        try repository.upsert(normal, historyLimit: 1)

        XCTAssertEqual(try repository.countNormalItems(), 1)
        XCTAssertEqual(Set(try repository.search("", limit: 10).map(\.id)), [favorite.id, pinned.id, normal.id])
    }

    func testRemovingFavoriteProtectionLazilyConvergesToLimit() throws {
        let database = try MacToolsDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let protected = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000121")!,
            title: "protected",
            createdAt: Date(timeIntervalSince1970: 1),
            isFavorite: true,
            contentHash: "protected"
        )
        let normal = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000122")!,
            title: "normal",
            createdAt: Date(timeIntervalSince1970: 2),
            contentHash: "normal-two"
        )
        try repository.upsert(protected)
        try repository.upsert(normal)

        try repository.setFavorite(id: protected.id, isFavorite: false, historyLimit: 1)

        XCTAssertEqual(try repository.search("", limit: 10).map(\.id), [normal.id])
    }

    func testPruningImageRemovesUnreferencedPayloadAfterCommit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPayloadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try MacToolsDatabase.inMemory()
        let payloadStore = PayloadStore(rootDirectory: root)
        let repository = ClipboardRepository(database: database, payloadStore: payloadStore)
        let firstPayload = try payloadStore.storePNG(Self.pngData(suffix: 1))
        let secondPayload = try payloadStore.storePNG(Self.pngData(suffix: 2))
        let first = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000131")!,
            kind: .imageData,
            title: "first image",
            createdAt: Date(timeIntervalSince1970: 1),
            contentHash: firstPayload.contentHash
        )
        let second = ClipboardItem.testItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000132")!,
            kind: .imageData,
            title: "second image",
            createdAt: Date(timeIntervalSince1970: 2),
            contentHash: secondPayload.contentHash
        )

        try repository.upsert(first, payload: firstPayload, historyLimit: 1)
        try repository.upsert(second, payload: secondPayload, historyLimit: 1)

        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(payloadStore.fileURL(for: firstPayload.relativePath)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(payloadStore.fileURL(for: secondPayload.relativePath)).path))
        XCTAssertEqual(try repository.search("", limit: 10).first?.cachedFilePath, payloadStore.fileURL(for: secondPayload.relativePath)?.path)
    }

    private static func pngData(suffix: UInt8) -> Data {
        var data = Data(base64Encoded: onePixelPNGBase64)!
        data.append(suffix)
        return data
    }

    private static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}

private extension ClipboardItem {
    static func testItem(
        id: UUID,
        kind: ClipboardContentKind = .text,
        title: String,
        searchableText: String? = nil,
        text: String? = nil,
        sourceApp: String? = nil,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        contentHash: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            displayTitle: title,
            searchableText: searchableText ?? title,
            text: text ?? title,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: sourceApp,
            contentHash: contentHash,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            useCount: useCount,
            isPinned: isPinned,
            isFavorite: isFavorite
        )
    }
}
