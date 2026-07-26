// `ClipboardDatabase` 的本地存储领域实现。
// 负责数据库、载荷文件和迁移事务，不管理运行时面板状态。

import Foundation
import GRDB

/// 管理 `MacToolsDatabase` 在本地存储领域中的生命周期、依赖和可变状态。
public final class MacToolsDatabase: @unchecked Sendable {
    public let writer: any DatabaseWriter

    /// 创建 `MacToolsDatabase`，保存传入依赖并建立初始状态。
    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// 计算并返回 `inMemory` 对应的本地存储领域数据或状态结果。
    public static func inMemory() throws -> MacToolsDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try MacToolsDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    /// 计算并返回 `at` 对应的本地存储领域数据或状态结果。
    public static func at(_ url: URL) throws -> MacToolsDatabase {
        let directoryURL = url.deletingLastPathComponent()
        try SensitiveFilePermissions.prepareDirectory(at: directoryURL)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let database = try MacToolsDatabase(
            writer: DatabasePool(path: url.path, configuration: configuration)
        )
        try secureDatabaseFiles(at: url)
        return database
    }

    /// 计算并返回 `secureDatabaseFiles` 对应的本地存储领域数据或状态结果。
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
        migrator.registerMigration("createUnifiedStoreV1") { db in
            try db.create(table: "payload_objects") { table in
                table.column("id", .text).primaryKey()
                table.column("contentHash", .text).notNull().unique()
                table.column("relativePath", .text).notNull().unique()
                table.column("format", .text).notNull()
                table.column("byteCount", .integer).notNull()
                table.column("localState", .text).notNull().defaults(to: "available")
                table.column("cloudState", .text).notNull().defaults(to: "localOnly")
                table.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "clipboard_items") { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("displayTitle", .text).notNull()
                table.column("searchableText", .text).notNull()
                table.column("text", .text)
                table.column("originalPath", .text)
                table.column("sourceApp", .text)
                table.column("contentHash", .text).unique()
                table.column("createdAt", .datetime).notNull()
                table.column("lastCapturedAt", .datetime).notNull()
                table.column("lastUsedAt", .datetime)
                table.column("retentionAt", .datetime).notNull()
                table.column("useCount", .integer).notNull()
                table.column("isPinned", .boolean).notNull()
                table.column("isFavorite", .boolean).notNull()
                table.column("payloadID", .text)
                    .references("payload_objects", onDelete: .setNull)
            }

            try db.create(
                index: "idx_clipboard_search",
                on: "clipboard_items",
                columns: ["searchableText", "displayTitle"]
            )
            try db.create(
                index: "idx_clipboard_display_order",
                on: "clipboard_items",
                columns: ["isPinned", "createdAt"]
            )
            try db.create(
                index: "idx_clipboard_retention",
                on: "clipboard_items",
                columns: ["isFavorite", "isPinned", "retentionAt", "createdAt", "id"]
            )
            try db.create(
                index: "idx_clipboard_payload",
                on: "clipboard_items",
                columns: ["payloadID"]
            )

            try db.create(table: "payload_gc_queue") { table in
                table.column("payloadID", .text).primaryKey()
                    .references("payload_objects", onDelete: .cascade)
                table.column("enqueuedAt", .datetime).notNull()
                table.column("attemptCount", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
            }

            try db.create(table: "preferences") { table in
                table.column("domain", .text).primaryKey()
                table.column("value", .blob).notNull()
                table.column("schemaVersion", .integer).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "device_overrides") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .blob).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "sync_metadata") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .blob).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "sync_outbox") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("recordType", .text).notNull()
                table.column("recordName", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("payload", .blob)
                table.column("createdAt", .datetime).notNull()
                table.column("attemptCount", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
                table.uniqueKey(["recordType", "recordName", "operation"])
            }

            try db.create(table: "tombstones") { table in
                table.column("recordName", .text).primaryKey()
                table.column("targetType", .text).notNull()
                table.column("generation", .integer).notNull()
                table.column("deletedAt", .datetime).notNull()
                table.column("uploadedAt", .datetime)
            }

            try db.create(table: "migration_state") { table in
                table.column("key", .text).primaryKey()
                table.column("completedAt", .datetime).notNull()
                table.column("details", .blob)
            }
        }
        migrator.registerMigration("hardenSyncStateV2") { db in
            try db.alter(table: "clipboard_items") { table in
                table.add(column: "syncGeneration", .integer).notNull().defaults(to: 1)
                table.add(column: "favoriteClock", .integer).notNull().defaults(to: 0)
                table.add(column: "favoriteDeviceID", .text).notNull().defaults(to: "")
                table.add(column: "pinnedClock", .integer).notNull().defaults(to: 0)
                table.add(column: "pinnedDeviceID", .text).notNull().defaults(to: "")
            }

            try db.create(table: "sync_outbox_v2") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("recordType", .text).notNull()
                table.column("recordName", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("generation", .integer).notNull().defaults(to: 1)
                table.column("payload", .blob)
                table.column("createdAt", .datetime).notNull()
                table.column("attemptCount", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
                table.uniqueKey(["recordType", "recordName"])
            }
            let legacyOutboxRows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM sync_outbox ORDER BY createdAt ASC, id ASC"
            )
            for row in legacyOutboxRows {
                try db.execute(
                    sql: """
                    INSERT INTO sync_outbox_v2 (
                        recordType, recordName, operation, generation, payload,
                        createdAt, attemptCount, lastError
                    ) VALUES (?, ?, ?, 1, ?, ?, ?, ?)
                    ON CONFLICT(recordType, recordName) DO UPDATE SET
                        operation = excluded.operation,
                        generation = excluded.generation,
                        payload = excluded.payload,
                        createdAt = excluded.createdAt,
                        attemptCount = excluded.attemptCount,
                        lastError = excluded.lastError
                    """,
                    arguments: [
                        row["recordType"] as String,
                        row["recordName"] as String,
                        row["operation"] as String,
                        row["payload"] as Data?,
                        row["createdAt"] as Date,
                        row["attemptCount"] as Int,
                        row["lastError"] as String?
                    ]
                )
            }
            try db.drop(table: "sync_outbox")
            try db.rename(table: "sync_outbox_v2", to: "sync_outbox")

            try db.alter(table: "tombstones") { table in
                table.add(column: "cloudRecordName", .text)
                table.add(column: "reason", .text).notNull().defaults(to: "user")
            }
            try db.execute(
                sql: """
                UPDATE tombstones
                SET cloudRecordName = 'tombstone.' || generation || '.' || recordName
                WHERE cloudRecordName IS NULL
                """
            )
            try db.create(
                index: "idx_tombstones_cloud_record",
                on: "tombstones",
                columns: ["cloudRecordName"],
                unique: true
            )

            try db.create(table: "sync_accounts") { table in
                table.column("accountHash", .text).primaryKey()
                table.column("engineState", .blob)
                table.column("resetGeneration", .integer).notNull().defaults(to: 1)
                table.column("requiresBootstrap", .boolean).notNull().defaults(to: true)
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "sync_record_metadata") { table in
                table.column("accountHash", .text).notNull()
                    .references("sync_accounts", onDelete: .cascade)
                table.column("recordType", .text).notNull()
                table.column("recordName", .text).notNull()
                table.column("generation", .integer).notNull()
                table.column("systemFields", .blob).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["accountHash", "recordType", "recordName"])
            }
            try db.create(table: "preference_field_clocks") { table in
                table.column("domain", .text).notNull()
                table.column("fieldPath", .text).notNull()
                table.column("counter", .integer).notNull()
                table.column("deviceID", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.primaryKey(["domain", "fieldPath"])
            }
        }
        migrator.registerMigration("trackLocalEvictionsV3") { db in
            try db.create(table: "local_clipboard_evictions") { table in
                table.column("recordName", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("evictedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("addDeviceReplicasV4") { db in
            try db.create(table: "device_replicas") { table in
                table.column("recordName", .text).primaryKey()
                table.column("targetRecordName", .text).notNull()
                table.column("deviceID", .text).notNull()
                table.column("generation", .integer).notNull()
                table.column("lastCapturedAt", .datetime).notNull()
                table.column("lastUsedAt", .datetime)
                table.column("useCount", .integer).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_device_replicas_target",
                on: "device_replicas",
                columns: ["targetRecordName"]
            )
        }
        migrator.registerMigration("addRecordAliasesV5") { db in
            try db.create(table: "sync_record_aliases") { table in
                table.column("loserRecordName", .text).primaryKey()
                table.column("winnerRecordName", .text).notNull()
                table.column("generation", .integer).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("cleanupOrphanedEvictionsV6") { db in
            try db.execute(
                sql: """
                DELETE FROM local_clipboard_evictions
                WHERE recordName NOT IN (
                    SELECT recordName
                    FROM sync_outbox
                    WHERE recordType = 'ClipboardContent' AND operation = 'save'
                )
                AND recordName NOT IN (
                    SELECT targetRecordName FROM device_replicas
                )
                """
            )
        }
        migrator.registerMigration("addDriveSyncStateV7") { db in
            try db.create(table: "file_sync_receipts") { table in
                table.column("deviceID", .text).primaryKey()
                table.column("generation", .integer).notNull()
                table.column("revision", .integer).notNull()
                table.column("manifestDigest", .text).notNull()
                table.column("appliedAt", .datetime).notNull()
            }
            try db.create(table: "sync_object_gc_observations") { table in
                table.column("contentID", .text).primaryKey()
                table.column("firstUnreferencedAt", .datetime).notNull()
            }
            try db.execute(sql: "DELETE FROM sync_record_metadata")
            try db.execute(sql: "DELETE FROM sync_accounts")
            try db.execute(
                sql: "DELETE FROM device_overrides WHERE key = 'sync.approvedAccountHash'"
            )
            try db.execute(sql: "DELETE FROM sync_outbox")
        }
        migrator.registerMigration("addTombstoneCausalityV8") { db in
            try db.alter(table: "tombstones") { table in
                table.add(column: "sourceDeviceID", .text).notNull().defaults(to: "")
                table.add(column: "sourceRevision", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("renameTombstoneIdentifierV9") { db in
            try db.alter(table: "tombstones") { table in
                table.rename(column: "cloudRecordName", to: "tombstoneID")
            }
        }
        return migrator
    }
}

/// 为本地存储领域中的相关类型提供 `ClipboardDatabase` 别名。
public typealias ClipboardDatabase = MacToolsDatabase
