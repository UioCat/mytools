import Foundation
import GRDB

public struct LegacyStoreMigrationReport: Codable, Equatable {
    public var importedClipboardItems: Int
    public var skippedMissingImages: Int
    public var skippedInvalidRecords: Int

    public init(
        importedClipboardItems: Int = 0,
        skippedMissingImages: Int = 0,
        skippedInvalidRecords: Int = 0
    ) {
        self.importedClipboardItems = importedClipboardItems
        self.skippedMissingImages = skippedMissingImages
        self.skippedInvalidRecords = skippedInvalidRecords
    }
}

public final class LegacyStoreMigrator {
    public static let migrationKey = "legacy-store-v1"

    private let database: MacToolsDatabase
    private let repository: ClipboardRepository
    private let payloadStore: PayloadStore
    private let fileManager: FileManager
    private let migrationDeviceID: String

    public init(
        database: MacToolsDatabase,
        repository: ClipboardRepository,
        payloadStore: PayloadStore,
        migrationDeviceID: String = UUID().uuidString,
        fileManager: FileManager = .default
    ) {
        self.database = database
        self.repository = repository
        self.payloadStore = payloadStore
        self.migrationDeviceID = migrationDeviceID
        self.fileManager = fileManager
    }

    public func migrateClipboardIfNeeded(
        from legacyDatabaseURL: URL,
        enqueuesSyncChanges: Bool = false
    ) throws -> LegacyStoreMigrationReport {
        if let existingReport = try completedReport() {
            return existingReport
        }

        guard fileManager.fileExists(atPath: legacyDatabaseURL.path) else {
            let report = LegacyStoreMigrationReport()
            try markCompleted(report)
            return report
        }

        let legacyDatabase = try DatabaseQueue(path: legacyDatabaseURL.path)
        let rows: [Row] = try legacyDatabase.read { db in
            guard try db.tableExists("clipboard_items") else {
                return []
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM clipboard_items ORDER BY createdAt ASC, id ASC")
        }

        var report = LegacyStoreMigrationReport()
        for row in rows {
            do {
                guard let kind = ClipboardContentKind(rawValue: row["kind"] as String) else {
                    report.skippedInvalidRecords += 1
                    continue
                }
                let text: String? = row.hasColumn("text") ? row["text"] : nil
                let originalPath: String? = row.hasColumn("originalPath") ? row["originalPath"] : nil
                let imageData: Data?
                if kind == .imageData {
                    let cachedFilePath: String? = row.hasColumn("cachedFilePath") ? row["cachedFilePath"] : nil
                    guard let cachedFilePath,
                          fileManager.fileExists(atPath: cachedFilePath) else {
                        report.skippedMissingImages += 1
                        continue
                    }
                    imageData = try Data(contentsOf: URL(fileURLWithPath: cachedFilePath))
                } else {
                    imageData = nil
                }

                let payload = ClipboardPayload(
                    text: text,
                    fileURLs: originalPath.map { [URL(fileURLWithPath: $0)] } ?? [],
                    imageData: imageData
                )
                let contentHash = ClipboardContentHasher.sha256(for: payload)
                guard contentHash != nil else {
                    report.skippedInvalidRecords += 1
                    continue
                }

                let createdAt: Date = row["createdAt"]
                let lastUsedAt: Date? = row.hasColumn("lastUsedAt") ? row["lastUsedAt"] : nil
                let idValue: String = row["id"]
                let item = ClipboardItem(
                    id: UUID(uuidString: idValue) ?? UUID(),
                    kind: kind,
                    displayTitle: row["displayTitle"],
                    searchableText: row["searchableText"],
                    text: text,
                    originalPath: originalPath,
                    cachedFilePath: nil,
                    thumbnailPath: nil,
                    sourceApp: row.hasColumn("sourceApp") ? row["sourceApp"] : nil,
                    contentHash: contentHash,
                    createdAt: createdAt,
                    lastUsedAt: lastUsedAt,
                    useCount: row.hasColumn("useCount") ? row["useCount"] : 0,
                    isPinned: row.hasColumn("isPinned") ? row["isPinned"] : false,
                    isFavorite: row.hasColumn("isFavorite") ? row["isFavorite"] : false,
                    lastCapturedAt: createdAt,
                    retentionAt: max(createdAt, lastUsedAt ?? .distantPast),
                    payloadID: nil,
                    favoriteClock: ClipboardFieldClock(counter: 1, deviceID: migrationDeviceID),
                    pinnedClock: ClipboardFieldClock(counter: 1, deviceID: migrationDeviceID)
                )
                if let imageData {
                    try repository.upsertPNG(
                        item,
                        data: imageData,
                        enqueuesSyncChange: enqueuesSyncChanges
                    )
                } else {
                    try repository.upsert(
                        item,
                        enqueuesSyncChange: enqueuesSyncChanges
                    )
                }
                report.importedClipboardItems += 1
            } catch is PayloadStoreError {
                report.skippedInvalidRecords += 1
            }
        }

        try markCompleted(report)
        return report
    }

    private func completedReport() throws -> LegacyStoreMigrationReport? {
        try database.writer.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT details FROM migration_state WHERE key = ?",
                arguments: [Self.migrationKey]
            ) else {
                return nil
            }
            return try JSONDecoder().decode(LegacyStoreMigrationReport.self, from: data)
        }
    }

    private func markCompleted(_ report: LegacyStoreMigrationReport) throws {
        let data = try JSONEncoder().encode(report)
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO migration_state (key, completedAt, details)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO NOTHING
                """,
                arguments: [Self.migrationKey, Date(), data]
            )
        }
    }
}
