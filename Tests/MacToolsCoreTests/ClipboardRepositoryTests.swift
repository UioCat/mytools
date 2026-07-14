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
