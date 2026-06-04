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

        _ = try ClipboardDatabase.at(databaseURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.deletingLastPathComponent().path))
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
        isFavorite: Bool = false
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
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            useCount: useCount,
            isPinned: isPinned,
            isFavorite: isFavorite
        )
    }
}
