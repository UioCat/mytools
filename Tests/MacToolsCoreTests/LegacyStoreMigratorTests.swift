import Foundation
import GRDB
import XCTest
@testable import MacToolsCore

final class LegacyStoreMigratorTests: XCTestCase {
    func testMigratesLegacyRowsAndImagesExactlyOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyStoreMigratorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacyDatabaseURL = root.appendingPathComponent("Clipboard.sqlite")
        let legacyImageURL = root.appendingPathComponent("legacy.png")
        try pngData().write(to: legacyImageURL)
        try makeLegacyDatabase(at: legacyDatabaseURL, imageURL: legacyImageURL)

        let database = try MacToolsDatabase.at(root.appendingPathComponent("Store/mactools.sqlite3"))
        let payloadStore = PayloadStore(rootDirectory: root.appendingPathComponent("Store/Payloads"))
        let repository = ClipboardRepository(database: database, payloadStore: payloadStore)
        let migrator = LegacyStoreMigrator(
            database: database,
            repository: repository,
            payloadStore: payloadStore,
            migrationDeviceID: "migration-device"
        )

        let first = try migrator.migrateClipboardIfNeeded(from: legacyDatabaseURL)
        let second = try migrator.migrateClipboardIfNeeded(from: legacyDatabaseURL)
        let items = try repository.search("", limit: 10)

        XCTAssertEqual(first.importedClipboardItems, 2)
        XCTAssertEqual(first.skippedMissingImages, 1)
        XCTAssertEqual(first.skippedInvalidRecords, 0)
        XCTAssertEqual(second, first)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(try repository.countNormalItems(), 2)
        XCTAssertEqual(items.first(where: { $0.kind == .text })?.text, "legacy text")
        let image = try XCTUnwrap(items.first(where: { $0.kind == .imageData }))
        XCTAssertEqual(image.contentHash?.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(image.cachedFilePath)))
        XCTAssertTrue(items.allSatisfy {
            $0.favoriteClock == ClipboardFieldClock(counter: 1, deviceID: "migration-device")
                && $0.pinnedClock == ClipboardFieldClock(counter: 1, deviceID: "migration-device")
        })
    }

    private func makeLegacyDatabase(at url: URL, imageURL: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.create(table: "clipboard_items") { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("displayTitle", .text).notNull()
                table.column("searchableText", .text).notNull()
                table.column("text", .text)
                table.column("originalPath", .text)
                table.column("cachedFilePath", .text)
                table.column("thumbnailPath", .text)
                table.column("sourceApp", .text)
                table.column("contentHash", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("lastUsedAt", .datetime)
                table.column("useCount", .integer).notNull()
                table.column("isPinned", .boolean).notNull()
                table.column("isFavorite", .boolean).notNull()
            }
            try insertLegacyRow(
                in: db,
                id: "00000000-0000-0000-0000-000000000201",
                kind: "text",
                title: "legacy text",
                text: "legacy text",
                cachedFilePath: nil,
                createdAt: Date(timeIntervalSince1970: 1)
            )
            try insertLegacyRow(
                in: db,
                id: "00000000-0000-0000-0000-000000000202",
                kind: "imageData",
                title: "legacy image",
                text: nil,
                cachedFilePath: imageURL.path,
                createdAt: Date(timeIntervalSince1970: 2)
            )
            try insertLegacyRow(
                in: db,
                id: "00000000-0000-0000-0000-000000000203",
                kind: "imageData",
                title: "missing image",
                text: nil,
                cachedFilePath: rootMissingPath(for: url),
                createdAt: Date(timeIntervalSince1970: 3)
            )
        }
    }

    private func insertLegacyRow(
        in db: Database,
        id: String,
        kind: String,
        title: String,
        text: String?,
        cachedFilePath: String?,
        createdAt: Date
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO clipboard_items (
                id, kind, displayTitle, searchableText, text, cachedFilePath,
                sourceApp, contentHash, createdAt, useCount, isPinned, isFavorite
            ) VALUES (?, ?, ?, ?, ?, ?, 'LegacyTests', 'legacy-md5', ?, 0, 0, 0)
            """,
            arguments: [id, kind, title, text ?? title, text, cachedFilePath, createdAt]
        )
    }

    private func rootMissingPath(for databaseURL: URL) -> String {
        databaseURL.deletingLastPathComponent().appendingPathComponent("missing.png").path
    }

    private func pngData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
}
