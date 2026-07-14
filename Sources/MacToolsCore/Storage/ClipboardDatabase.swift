import Foundation
import GRDB

public final class ClipboardDatabase {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func inMemory() throws -> ClipboardDatabase {
        try ClipboardDatabase(writer: DatabaseQueue())
    }

    public static func at(_ url: URL) throws -> ClipboardDatabase {
        let directoryURL = url.deletingLastPathComponent()
        try SensitiveFilePermissions.prepareDirectory(at: directoryURL)
        let database = try ClipboardDatabase(writer: DatabaseQueue(path: url.path))
        try secureDatabaseFiles(at: url)
        return database
    }

    private static func secureDatabaseFiles(at url: URL) throws {
        for suffix in ["", "-shm", "-wal", "-journal"] {
            let fileURL = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            try SensitiveFilePermissions.secureFile(at: fileURL)
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createClipboardItems") { db in
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

            try db.create(
                index: "idx_clipboard_search",
                on: "clipboard_items",
                columns: ["searchableText", "displayTitle"]
            )
            try db.create(
                index: "idx_clipboard_order",
                on: "clipboard_items",
                columns: ["isPinned", "createdAt"]
            )
            try db.create(
                index: "idx_clipboard_last_used",
                on: "clipboard_items",
                columns: ["lastUsedAt"]
            )
        }
        migrator.registerMigration("indexClipboardContentHash") { db in
            let columns = try db.columns(in: "clipboard_items")
            if !columns.contains(where: { $0.name == "contentHash" }) {
                try db.alter(table: "clipboard_items") { table in
                    table.add(column: "contentHash", .text)
                }
            }
            try db.create(
                index: "idx_clipboard_content_hash",
                on: "clipboard_items",
                columns: ["contentHash"],
                unique: true
            )
        }
        return migrator
    }
}
