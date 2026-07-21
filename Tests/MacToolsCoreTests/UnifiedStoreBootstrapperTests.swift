import Foundation
import GRDB
import XCTest
@testable import MacToolsCore

final class UnifiedStoreBootstrapperTests: XCTestCase {
    func testBuildsVerifiedStagedStoreThenPreservesIncompleteStoreAsRollback() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = MacToolsStorePaths(supportDirectory: root)
        try makeLegacyDatabase(at: paths.legacyDatabaseURL)
        try FileManager.default.createDirectory(at: paths.storeDirectory, withIntermediateDirectories: true)
        try Data("incomplete".utf8).write(to: paths.storeDirectory.appendingPathComponent("sentinel"))
        do {
            let incompleteDatabase = try MacToolsDatabase.at(paths.databaseURL)
            let incompleteRepository = ClipboardRepository(database: incompleteDatabase)
            try incompleteRepository.upsert(ClipboardItem(
                id: UUID(),
                kind: .text,
                displayTitle: "created after partial migration",
                searchableText: "created after partial migration",
                text: "created after partial migration",
                originalPath: nil,
                cachedFilePath: nil,
                thumbnailPath: nil,
                sourceApp: nil,
                contentHash: "partial-new-record",
                createdAt: Date(timeIntervalSince1970: 2),
                lastUsedAt: nil,
                useCount: 0,
                isPinned: false,
                isFavorite: false
            ))
        }

        var settings = AppSettings.defaults
        settings.appearanceMode = .dark
        settings.translation.apiKey = "must-not-enter-sqlite"
        let result = try UnifiedStoreBootstrapper.prepare(paths: paths, legacySettings: settings)

        XCTAssertTrue(result.didCutOver)
        let rollback = try XCTUnwrap(result.rollbackDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollback.appendingPathComponent("sentinel").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.legacyDatabaseURL.path))

        let database = try MacToolsDatabase.at(paths.databaseURL)
        let repository = ClipboardRepository(
            database: database,
            payloadStore: PayloadStore(rootDirectory: paths.payloadsDirectory)
        )
        XCTAssertEqual(try repository.search("", limit: 10).count, 2)
        XCTAssertEqual(try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox")
        }, 0)
        let stored = try XCTUnwrap(PreferenceRepository(database: database).rawData())
        XCTAssertFalse(String(decoding: stored, as: UTF8.self).contains("must-not-enter-sqlite"))
    }

    func testMigrationFailureDoesNotReplaceExistingStore() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = MacToolsStorePaths(supportDirectory: root)
        try FileManager.default.createDirectory(at: paths.storeDirectory, withIntermediateDirectories: true)
        let sentinel = paths.storeDirectory.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        try Data("not-a-database".utf8).write(to: paths.legacyDatabaseURL)

        XCTAssertThrowsError(
            try UnifiedStoreBootstrapper.prepare(paths: paths, legacySettings: .defaults)
        )
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    func testCorruptIncompleteStoreIsQuarantinedAndRebuiltFromLegacySource() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = MacToolsStorePaths(supportDirectory: root)
        try makeLegacyDatabase(at: paths.legacyDatabaseURL)
        try FileManager.default.createDirectory(at: paths.storeDirectory, withIntermediateDirectories: true)
        try Data("not-a-database".utf8).write(to: paths.databaseURL)

        let result = try UnifiedStoreBootstrapper.prepare(paths: paths, legacySettings: .defaults)

        XCTAssertTrue(result.didCutOver)
        let rollback = try XCTUnwrap(result.rollbackDirectory)
        XCTAssertEqual(
            try Data(contentsOf: rollback.appendingPathComponent("mactools.sqlite3")),
            Data("not-a-database".utf8)
        )
        let database = try MacToolsDatabase.at(paths.databaseURL)
        XCTAssertEqual(try ClipboardRepository(database: database).search("", limit: 10).count, 1)
    }

    func testInMemoryFallbackReconcileCannotDeletePersistentPayloads() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = MacToolsStorePaths(supportDirectory: root)
        let persistentObject = paths.payloadsDirectory
            .appendingPathComponent("objects/sha256/aa/sentinel.png")
        try FileManager.default.createDirectory(
            at: persistentObject.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: persistentObject)
        let fallbackDirectory = paths.runtimePayloadsDirectory(
            persistentStoreAvailable: false,
            temporaryDirectory: root.appendingPathComponent("Temporary", isDirectory: true)
        )
        let database = try MacToolsDatabase.inMemory()
        let repository = ClipboardRepository(
            database: database,
            payloadStore: PayloadStore(rootDirectory: fallbackDirectory)
        )

        try repository.reconcilePayloadStorage()

        XCTAssertNotEqual(fallbackDirectory.standardizedFileURL, paths.payloadsDirectory.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: persistentObject), Data("keep".utf8))
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnifiedStoreBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeLegacyDatabase(at url: URL) throws {
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
                table.column("sourceApp", .text)
                table.column("createdAt", .datetime).notNull()
                table.column("lastUsedAt", .datetime)
                table.column("useCount", .integer).notNull()
                table.column("isPinned", .boolean).notNull()
                table.column("isFavorite", .boolean).notNull()
            }
            try db.execute(
                sql: """
                INSERT INTO clipboard_items (
                    id, kind, displayTitle, searchableText, text, createdAt,
                    useCount, isPinned, isFavorite
                ) VALUES (?, 'text', 'legacy', 'legacy', 'legacy', ?, 0, 0, 0)
                """,
                arguments: [UUID().uuidString, Date(timeIntervalSince1970: 1)]
            )
        }
    }
}
