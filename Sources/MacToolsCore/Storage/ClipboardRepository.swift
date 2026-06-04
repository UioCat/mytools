import Foundation
import GRDB

public final class ClipboardRepository {
    private let database: ClipboardDatabase

    public init(database: ClipboardDatabase) {
        self.database = database
    }

    public func upsert(_ item: ClipboardItem) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO clipboard_items (
                    id, kind, displayTitle, searchableText, text, originalPath,
                    cachedFilePath, thumbnailPath, sourceApp, contentHash, createdAt,
                    lastUsedAt, useCount, isPinned, isFavorite
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(contentHash) DO UPDATE SET
                    kind = excluded.kind,
                    displayTitle = excluded.displayTitle,
                    searchableText = excluded.searchableText,
                    text = excluded.text,
                    originalPath = excluded.originalPath,
                    cachedFilePath = COALESCE(excluded.cachedFilePath, clipboard_items.cachedFilePath),
                    thumbnailPath = COALESCE(excluded.thumbnailPath, clipboard_items.thumbnailPath),
                    sourceApp = excluded.sourceApp,
                    createdAt = excluded.createdAt
                """,
                arguments: [
                    item.id.uuidString,
                    item.kind.rawValue,
                    item.displayTitle,
                    item.searchableText,
                    item.text,
                    item.originalPath,
                    item.cachedFilePath,
                    item.thumbnailPath,
                    item.sourceApp,
                    item.contentHash,
                    item.createdAt,
                    item.lastUsedAt,
                    item.useCount,
                    item.isPinned,
                    item.isFavorite
                ]
            )
        }
    }

    public func search(_ query: String, limit: Int) throws -> [ClipboardItem] {
        try search(query, limit: limit, favoritesOnly: false)
    }

    public func search(_ query: String, limit: Int, favoritesOnly: Bool) throws -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(limit, 0)

        return try database.writer.read { db in
            let favoriteClause = favoritesOnly ? "WHERE isFavorite = 1" : ""
            if trimmedQuery.isEmpty {
                return try ClipboardItem.fetchAll(
                    db,
                    sql: """
                    SELECT *
                    FROM clipboard_items
                    \(favoriteClause)
                    ORDER BY isPinned DESC, createdAt DESC
                    LIMIT ?
                    """,
                    arguments: [boundedLimit]
                )
            }

            let pattern = Self.likePattern(for: trimmedQuery)
            let prefix = favoritesOnly ? "WHERE isFavorite = 1 AND" : "WHERE"
            return try ClipboardItem.fetchAll(
                db,
                sql: """
                SELECT *
                FROM clipboard_items
                \(prefix) (searchableText LIKE ? ESCAPE '\\'
                   OR displayTitle LIKE ? ESCAPE '\\'
                )
                ORDER BY isPinned DESC, createdAt DESC
                LIMIT ?
                """,
                arguments: [pattern, pattern, boundedLimit]
            )
        }
    }

    public func setFavorite(id: UUID, isFavorite: Bool) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET isFavorite = ?
                WHERE id = ?
                """,
                arguments: [isFavorite, id.uuidString]
            )
        }
    }

    public func markUsed(id: UUID, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET lastUsedAt = ?, useCount = useCount + 1
                WHERE id = ?
                """,
                arguments: [date, id.uuidString]
            )
        }
    }

    private static func likePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}

extension ClipboardItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "clipboard_items"

    public init(row: Row) throws {
        let idValue: String = row["id"]
        guard let id = UUID(uuidString: idValue) else {
            throw ClipboardRecordError.invalidUUID(idValue)
        }

        let kindValue: String = row["kind"]
        guard let kind = ClipboardContentKind(rawValue: kindValue) else {
            throw ClipboardRecordError.invalidKind(kindValue)
        }

        self.init(
            id: id,
            kind: kind,
            displayTitle: row["displayTitle"],
            searchableText: row["searchableText"],
            text: row["text"],
            originalPath: row["originalPath"],
            cachedFilePath: row["cachedFilePath"],
            thumbnailPath: row["thumbnailPath"],
            sourceApp: row["sourceApp"],
            contentHash: row["contentHash"],
            createdAt: row["createdAt"],
            lastUsedAt: row["lastUsedAt"],
            useCount: row["useCount"],
            isPinned: row["isPinned"],
            isFavorite: row["isFavorite"]
        )
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["kind"] = kind.rawValue
        container["displayTitle"] = displayTitle
        container["searchableText"] = searchableText
        container["text"] = text
        container["originalPath"] = originalPath
        container["cachedFilePath"] = cachedFilePath
        container["thumbnailPath"] = thumbnailPath
        container["sourceApp"] = sourceApp
        container["contentHash"] = contentHash
        container["createdAt"] = createdAt
        container["lastUsedAt"] = lastUsedAt
        container["useCount"] = useCount
        container["isPinned"] = isPinned
        container["isFavorite"] = isFavorite
    }
}

private enum ClipboardRecordError: Error {
    case invalidUUID(String)
    case invalidKind(String)
}
