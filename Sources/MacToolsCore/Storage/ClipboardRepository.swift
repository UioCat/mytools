import Foundation
import GRDB

public struct ClipboardUpsertResult: Equatable {
    public let itemID: UUID
    public let inserted: Bool
    public let prunedItemIDs: [UUID]
    public let duplicateRecordIDs: [UUID]

    public init(
        itemID: UUID,
        inserted: Bool,
        prunedItemIDs: [UUID],
        duplicateRecordIDs: [UUID] = []
    ) {
        self.itemID = itemID
        self.inserted = inserted
        self.prunedItemIDs = prunedItemIDs
        self.duplicateRecordIDs = duplicateRecordIDs
    }
}

public final class ClipboardRepository: @unchecked Sendable {
    private let database: MacToolsDatabase
    private let payloadStore: PayloadStore?
    private let garbageCollector: PayloadGarbageCollector?

    public init(database: MacToolsDatabase, payloadStore: PayloadStore? = nil) {
        self.database = database
        self.payloadStore = payloadStore
        self.garbageCollector = payloadStore.map {
            PayloadGarbageCollector(database: database, payloadStore: $0)
        }
    }

    @discardableResult
    public func upsert(
        _ item: ClipboardItem,
        payload: PayloadObjectDescriptor? = nil,
        historyLimit: Int? = nil,
        enqueuesSyncChange: Bool = true,
        deterministicallyMergesRecordNames: Bool = false
    ) throws -> ClipboardUpsertResult {
        let write = {
            try self.database.writer.write { db in
            if let payload {
                guard self.payloadStore?.contains(relativePath: payload.relativePath) ?? true else {
                    throw PayloadStoreError.missingObject
                }
                try self.upsertPayload(payload, in: db, at: item.createdAt)
            }

            let existing = try Row.fetchOne(
                db,
                sql: """
                SELECT id, createdAt, lastCapturedAt, lastUsedAt, retentionAt, payloadID,
                       isFavorite, favoriteClock, favoriteDeviceID,
                       isPinned, pinnedClock, pinnedDeviceID, syncGeneration
                FROM clipboard_items
                WHERE contentHash = ?
                """,
                arguments: [item.contentHash]
            )
            let inserted = existing == nil
            let existingID = try existing.map { try Self.uuid(from: $0["id"] as String) }
            let persistedID: UUID
            let duplicateRecordIDs: [UUID]
            if let existingID, deterministicallyMergesRecordNames, existingID != item.id {
                persistedID = existingID.uuidString < item.id.uuidString ? existingID : item.id
                duplicateRecordIDs = [existingID.uuidString < item.id.uuidString ? item.id : existingID]
                if persistedID == item.id {
                    try db.execute(
                        sql: "UPDATE clipboard_items SET id = ? WHERE id = ?",
                        arguments: [item.id.uuidString, existingID.uuidString]
                    )
                }
            } else {
                persistedID = existingID ?? item.id
                duplicateRecordIDs = []
            }
            let createdAt = min(existing?["createdAt"] ?? item.createdAt, item.createdAt)
            let existingLastUsedAt: Date? = existing?["lastUsedAt"]
            let lastUsedAt = Self.latest(existingLastUsedAt, item.lastUsedAt)
            let existingLastCapturedAt: Date? = existing?["lastCapturedAt"]
            let lastCapturedAt = max(existingLastCapturedAt ?? .distantPast, item.lastCapturedAt)
            let existingRetentionAt: Date? = existing?["retentionAt"]
            let retentionAt = max(
                existingRetentionAt ?? .distantPast,
                max(lastCapturedAt, lastUsedAt ?? .distantPast)
            )
            let existingPayloadID: String? = existing?["payloadID"]
            let payloadID = payload?.id ?? item.payloadID ?? existingPayloadID
            let existingFavoriteClock = ClipboardFieldClock(
                counter: existing?["favoriteClock"] ?? 0,
                deviceID: existing?["favoriteDeviceID"] ?? ""
            )
            let existingIsFavorite: Bool = existing?["isFavorite"] ?? false
            let favoriteUsesIncoming = existing == nil || item.favoriteClock.shouldReplace(
                currentClock: existingFavoriteClock,
                incomingValue: item.isFavorite,
                currentValue: existingIsFavorite
            )
            let favoriteClock = favoriteUsesIncoming ? item.favoriteClock : existingFavoriteClock
            let isFavorite = favoriteUsesIncoming ? item.isFavorite : existingIsFavorite
            let existingPinnedClock = ClipboardFieldClock(
                counter: existing?["pinnedClock"] ?? 0,
                deviceID: existing?["pinnedDeviceID"] ?? ""
            )
            let existingIsPinned: Bool = existing?["isPinned"] ?? false
            let pinnedUsesIncoming = existing == nil || item.pinnedClock.shouldReplace(
                currentClock: existingPinnedClock,
                incomingValue: item.isPinned,
                currentValue: existingIsPinned
            )
            let pinnedClock = pinnedUsesIncoming ? item.pinnedClock : existingPinnedClock
            let isPinned = pinnedUsesIncoming ? item.isPinned : existingIsPinned
            let syncGeneration = max(
                existing?["syncGeneration"] ?? 1,
                enqueuesSyncChange ? try self.currentSyncGeneration(in: db) : item.syncGeneration
            )

            try db.execute(
                sql: """
                INSERT INTO clipboard_items (
                    id, kind, displayTitle, searchableText, text, originalPath,
                    sourceApp, contentHash, createdAt, lastCapturedAt, lastUsedAt,
                    retentionAt, useCount, isPinned, isFavorite, payloadID,
                    syncGeneration, favoriteClock, favoriteDeviceID,
                    pinnedClock, pinnedDeviceID
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(contentHash) DO UPDATE SET
                    kind = excluded.kind,
                    displayTitle = excluded.displayTitle,
                    searchableText = excluded.searchableText,
                    text = excluded.text,
                    originalPath = excluded.originalPath,
                    sourceApp = excluded.sourceApp,
                    lastCapturedAt = excluded.lastCapturedAt,
                    lastUsedAt = excluded.lastUsedAt,
                    retentionAt = excluded.retentionAt,
                    useCount = MAX(clipboard_items.useCount, excluded.useCount),
                    isPinned = excluded.isPinned,
                    isFavorite = excluded.isFavorite,
                    payloadID = COALESCE(excluded.payloadID, clipboard_items.payloadID),
                    syncGeneration = excluded.syncGeneration,
                    favoriteClock = excluded.favoriteClock,
                    favoriteDeviceID = excluded.favoriteDeviceID,
                    pinnedClock = excluded.pinnedClock,
                    pinnedDeviceID = excluded.pinnedDeviceID
                """,
                arguments: [
                    persistedID.uuidString,
                    item.kind.rawValue,
                    item.displayTitle,
                    item.searchableText,
                    item.text,
                    item.originalPath,
                    item.sourceApp,
                    item.contentHash,
                    createdAt,
                    lastCapturedAt,
                    lastUsedAt,
                    retentionAt,
                    item.useCount,
                    isPinned,
                    isFavorite,
                    payloadID,
                    syncGeneration,
                    favoriteClock.counter,
                    favoriteClock.deviceID,
                    pinnedClock.counter,
                    pinnedClock.deviceID
                ]
            )
            if deterministicallyMergesRecordNames {
                for duplicateID in duplicateRecordIDs {
                    try self.recordAlias(
                        loserRecordName: duplicateID.uuidString,
                        winnerRecordName: persistedID.uuidString,
                        generation: syncGeneration,
                        in: db
                    )
                }
                try self.mergeReplicaActivity(
                    targetRecordName: persistedID.uuidString,
                    in: db
                )
            }
            try db.execute(
                sql: "DELETE FROM local_clipboard_evictions WHERE recordName = ?",
                arguments: [persistedID.uuidString]
            )
            if enqueuesSyncChange, Self.isSyncable(item.kind) {
                try self.enqueueSyncChange(
                    recordType: SyncRecordType.clipboardContent.rawValue,
                    recordName: persistedID.uuidString,
                    operation: "save",
                    in: db
                )
                try self.upsertLocalDeviceReplica(
                    recordName: persistedID.uuidString,
                    lastCapturedAt: lastCapturedAt,
                    lastUsedAt: lastUsedAt,
                    useCount: item.useCount,
                    generation: syncGeneration,
                    in: db
                )
            }

            let prunedItemIDs: [UUID]
            if inserted, let historyLimit {
                prunedItemIDs = try self.pruneNormalHistory(in: db, limit: historyLimit)
            } else {
                prunedItemIDs = []
            }

            return ClipboardUpsertResult(
                itemID: persistedID,
                inserted: inserted,
                prunedItemIDs: prunedItemIDs,
                duplicateRecordIDs: duplicateRecordIDs
            )
            }
        }
        let result: ClipboardUpsertResult
        if let payloadStore {
            result = try payloadStore.withExclusiveAccess(write)
        } else {
            result = try write()
        }
        collectPayloadGarbageAfterCommit()
        return result
    }

    @discardableResult
    public func upsertPNG(
        _ item: ClipboardItem,
        data: Data,
        historyLimit: Int? = nil,
        enqueuesSyncChange: Bool = true
    ) throws -> ClipboardUpsertResult {
        guard let payloadStore else {
            throw PayloadStoreError.missingObject
        }
        return try payloadStore.withExclusiveAccess {
            let payload = try payloadStore.storePNG(data)
            do {
                return try upsert(
                    item,
                    payload: payload,
                    historyLimit: historyLimit,
                    enqueuesSyncChange: enqueuesSyncChange
                )
            } catch {
                payloadStore.discardIfCreated(payload)
                throw error
            }
        }
    }

    public func search(_ query: String, limit: Int) throws -> [ClipboardItem] {
        try search(query, limit: limit, favoritesOnly: false)
    }

    public func search(_ query: String, limit: Int, favoritesOnly: Bool) throws -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedLimit = max(limit, 0)
        let payloadRootPath = payloadStore?.rootDirectory.path

        return try database.writer.read { db in
            let favoriteClause = favoritesOnly ? "WHERE ci.isFavorite = 1" : ""
            if trimmedQuery.isEmpty {
                return try ClipboardItem.fetchAll(
                    db,
                    sql: """
                    \(Self.selectClipboardItemsSQL)
                    \(favoriteClause)
                    ORDER BY ci.isPinned DESC, ci.lastCapturedAt DESC, ci.createdAt DESC
                    LIMIT ?
                    """,
                    arguments: [payloadRootPath, payloadRootPath, boundedLimit]
                )
            }

            let pattern = Self.likePattern(for: trimmedQuery)
            let prefix = favoritesOnly ? "WHERE ci.isFavorite = 1 AND" : "WHERE"
            return try ClipboardItem.fetchAll(
                db,
                sql: """
                \(Self.selectClipboardItemsSQL)
                \(prefix) (ci.searchableText LIKE ? ESCAPE '\\'
                   OR ci.displayTitle LIKE ? ESCAPE '\\'
                )
                ORDER BY ci.isPinned DESC, ci.lastCapturedAt DESC, ci.createdAt DESC
                LIMIT ?
                """,
                arguments: [payloadRootPath, payloadRootPath, pattern, pattern, boundedLimit]
            )
        }
    }

    public func item(id: UUID) throws -> ClipboardItem? {
        let payloadRootPath = payloadStore?.rootDirectory.path
        return try database.writer.read { db in
            try ClipboardItem.fetchOne(
                db,
                sql: """
                \(Self.selectClipboardItemsSQL)
                WHERE ci.id = ?
                """,
                arguments: [payloadRootPath, payloadRootPath, id.uuidString]
            )
        }
    }

    public func setFavorite(id: UUID, isFavorite: Bool, historyLimit: Int? = nil) throws {
        try database.writer.write { db in
            let deviceID = try self.deviceID(in: db)
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET isFavorite = ?, favoriteClock = favoriteClock + 1, favoriteDeviceID = ?
                WHERE id = ?
                """,
                arguments: [isFavorite, deviceID, id.uuidString]
            )
            if !isFavorite, let historyLimit {
                _ = try pruneNormalHistory(in: db, limit: historyLimit)
            }
            try enqueueSyncChangeIfSyncable(recordName: id.uuidString, operation: "save", in: db)
        }
        collectPayloadGarbageAfterCommit()
    }

    public func setPinned(id: UUID, isPinned: Bool, historyLimit: Int? = nil) throws {
        try database.writer.write { db in
            let deviceID = try self.deviceID(in: db)
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET isPinned = ?, pinnedClock = pinnedClock + 1, pinnedDeviceID = ?
                WHERE id = ?
                """,
                arguments: [isPinned, deviceID, id.uuidString]
            )
            if !isPinned, let historyLimit {
                _ = try pruneNormalHistory(in: db, limit: historyLimit)
            }
            try enqueueSyncChangeIfSyncable(recordName: id.uuidString, operation: "save", in: db)
        }
        collectPayloadGarbageAfterCommit()
    }

    public func delete(id: UUID, createsTombstone: Bool = true) throws {
        try database.writer.write { db in
            let kind = try String.fetchOne(
                db,
                sql: "SELECT kind FROM clipboard_items WHERE id = ?",
                arguments: [id.uuidString]
            ).flatMap(ClipboardContentKind.init(rawValue:))
            let payloadIDs = try String.fetchAll(
                db,
                sql: "SELECT payloadID FROM clipboard_items WHERE id = ? AND payloadID IS NOT NULL",
                arguments: [id.uuidString]
            )
            try db.execute(sql: "DELETE FROM clipboard_items WHERE id = ?", arguments: [id.uuidString])
            try enqueueUnreferencedPayloads(payloadIDs, in: db)
            if createsTombstone, let kind, Self.isSyncable(kind) {
                try enqueueTombstones([id], in: db)
                try enqueueReplicaDeletions(targetRecordNames: [id.uuidString], in: db)
            }
        }
        collectPayloadGarbageAfterCommit()
    }

    public func deleteAllNonFavorites() throws {
        try database.writer.write { db in
            let payloadIDs = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT payloadID FROM clipboard_items WHERE isFavorite = 0 AND payloadID IS NOT NULL"
            )
            let itemIDs = try String.fetchAll(
                db,
                sql: """
                SELECT id FROM clipboard_items
                WHERE isFavorite = 0 AND kind IN ('text', 'url', 'imageData')
                """
            ).compactMap(UUID.init(uuidString:))
            try db.execute(sql: "DELETE FROM clipboard_items WHERE isFavorite = 0")
            try enqueueUnreferencedPayloads(payloadIDs, in: db)
            try enqueueTombstones(itemIDs, in: db)
            try enqueueReplicaDeletions(targetRecordNames: itemIDs.map(\.uuidString), in: db)
        }
        collectPayloadGarbageAfterCommit()
    }

    public func markUsed(id: UUID, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET lastUsedAt = ?, retentionAt = MAX(retentionAt, ?), useCount = useCount + 1
                WHERE id = ?
                """,
                arguments: [date, date, id.uuidString]
            )
            try enqueueSyncChangeIfSyncable(recordName: id.uuidString, operation: "save", in: db)
            if let row = try Row.fetchOne(
                db,
                sql: """
                SELECT kind, lastCapturedAt, lastUsedAt, useCount, syncGeneration
                FROM clipboard_items WHERE id = ?
                """,
                arguments: [id.uuidString]
            ), let kind = ClipboardContentKind(rawValue: row["kind"] as String),
               Self.isSyncable(kind) {
                try upsertLocalDeviceReplica(
                    recordName: id.uuidString,
                    lastCapturedAt: row["lastCapturedAt"],
                    lastUsedAt: row["lastUsedAt"],
                    useCount: row["useCount"],
                    generation: row["syncGeneration"],
                    in: db
                )
            }
        }
    }

    public func countNormalItems() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM clipboard_items WHERE isFavorite = 0 AND isPinned = 0"
            ) ?? 0
        }
    }

    @discardableResult
    public func enforceHistoryLimit(_ historyLimit: Int) throws -> [UUID] {
        let prunedItemIDs = try database.writer.write { db in
            try pruneNormalHistory(in: db, limit: historyLimit)
        }
        collectPayloadGarbageAfterCommit()
        return prunedItemIDs
    }

    public func collectPayloadGarbage() throws {
        try garbageCollector?.collect()
    }

    public func reconcilePayloadStorage() throws {
        guard let payloadStore else { return }
        try payloadStore.withExclusiveAccess {
            let knownRows: [(id: String, relativePath: String, referenceCount: Int)] = try database.writer.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                    SELECT po.id, po.relativePath, COUNT(ci.id) AS referenceCount
                    FROM payload_objects AS po
                    LEFT JOIN clipboard_items AS ci ON ci.payloadID = po.id
                    GROUP BY po.id, po.relativePath
                    """
                ).map { row in
                    (row["id"], row["relativePath"], row["referenceCount"])
                }
            }
            let knownPaths = Set(knownRows.map(\.relativePath))
            for orphanPath in try payloadStore.objectRelativePaths() where !knownPaths.contains(orphanPath) {
                try payloadStore.remove(relativePath: orphanPath)
            }
            try database.writer.write { db in
                for row in knownRows {
                    if row.referenceCount == 0 {
                        try enqueueUnreferencedPayloads([row.id], in: db)
                    } else if payloadStore.contains(relativePath: row.relativePath) {
                        try db.execute(
                            sql: "UPDATE payload_objects SET localState = 'available' WHERE id = ?",
                            arguments: [row.id]
                        )
                    } else {
                        try db.execute(
                            sql: "UPDATE payload_objects SET localState = 'missing' WHERE id = ?",
                            arguments: [row.id]
                        )
                    }
                }
            }
        }
        try collectPayloadGarbage()
    }

    @discardableResult
    public func cleanupOrphanedLocalEvictions() throws -> Int {
        try database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM local_clipboard_evictions
                WHERE recordName IN (
                    SELECT e.recordName
                    FROM local_clipboard_evictions AS e
                    LEFT JOIN sync_outbox AS so
                      ON so.recordType = ?
                     AND so.recordName = e.recordName
                     AND so.operation = 'save'
                    LEFT JOIN device_replicas AS dr
                      ON dr.targetRecordName = e.recordName
                    WHERE so.recordName IS NULL AND dr.recordName IS NULL
                )
                """,
                arguments: [SyncRecordType.clipboardContent.rawValue]
            )
            return db.changesCount
        }
    }

    private func upsertPayload(
        _ payload: PayloadObjectDescriptor,
        in db: Database,
        at date: Date
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO payload_objects (
                id, contentHash, relativePath, format, byteCount, localState, cloudState, createdAt
            ) VALUES (?, ?, ?, ?, ?, 'available', 'localOnly', ?)
            ON CONFLICT(id) DO UPDATE SET
                relativePath = excluded.relativePath,
                format = excluded.format,
                byteCount = excluded.byteCount,
                localState = 'available'
            """,
            arguments: [
                payload.id,
                payload.contentHash,
                payload.relativePath,
                payload.format,
                payload.byteCount,
                date
            ]
        )
        try db.execute(sql: "DELETE FROM payload_gc_queue WHERE payloadID = ?", arguments: [payload.id])
    }

    private func pruneNormalHistory(in db: Database, limit: Int) throws -> [UUID] {
        let boundedLimit = max(limit, 0)
        let normalCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM clipboard_items WHERE isFavorite = 0 AND isPinned = 0"
        ) ?? 0
        let overflow = max(normalCount - boundedLimit, 0)
        guard overflow > 0 else {
            return []
        }

        let victims = try Row.fetchAll(
            db,
            sql: """
            SELECT id, payloadID, kind
            FROM clipboard_items
            WHERE isFavorite = 0 AND isPinned = 0
            ORDER BY retentionAt ASC, createdAt ASC, id ASC
            LIMIT ?
            """,
            arguments: [overflow]
        )
        let itemIDs = try victims.map { try Self.uuid(from: $0["id"] as String) }
        let payloadIDs: [String] = victims.compactMap { row in row["payloadID"] }

        let placeholders = Array(repeating: "?", count: itemIDs.count).joined(separator: ",")
        try db.execute(
            sql: "DELETE FROM clipboard_items WHERE id IN (\(placeholders))",
            arguments: StatementArguments(itemIDs.map(\.uuidString))
        )
        try enqueueUnreferencedPayloads(payloadIDs, in: db)
        for victim in victims {
            let recordName = victim["id"] as String
            guard let kind = ClipboardContentKind(rawValue: victim["kind"] as String),
                  Self.isSyncable(kind) else {
                continue
            }
            let hasPendingContentSave = (try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM sync_outbox
                WHERE recordType = ? AND recordName = ? AND operation = 'save'
                """,
                arguments: [SyncRecordType.clipboardContent.rawValue, recordName]
            ) ?? 0) > 0
            let hasDeviceReplica = (try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM device_replicas WHERE targetRecordName = ?",
                arguments: [recordName]
            ) ?? 0) > 0
            guard hasPendingContentSave || hasDeviceReplica else {
                continue
            }
            try db.execute(
                sql: """
                INSERT INTO local_clipboard_evictions (recordName, kind, evictedAt)
                VALUES (?, ?, ?)
                ON CONFLICT(recordName) DO UPDATE SET
                    kind = excluded.kind,
                    evictedAt = excluded.evictedAt
                """,
                arguments: [recordName, kind.rawValue, Date()]
            )
        }
        return itemIDs
    }

    private func enqueueUnreferencedPayloads(_ payloadIDs: [String], in db: Database) throws {
        for payloadID in Set(payloadIDs) {
            let referenceCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM clipboard_items WHERE payloadID = ?",
                arguments: [payloadID]
            ) ?? 0
            guard referenceCount == 0 else {
                continue
            }
            try db.execute(
                sql: """
                INSERT INTO payload_gc_queue (payloadID, enqueuedAt, attemptCount)
                VALUES (?, ?, 0)
                ON CONFLICT(payloadID) DO NOTHING
                """,
                arguments: [payloadID, Date()]
            )
        }
    }

    private func enqueueTombstones(_ itemIDs: [UUID], in db: Database) throws {
        let generation = try currentSyncGeneration(in: db)
        for itemID in itemIDs {
            let tombstoneID = "tombstone.\(generation).\(itemID.uuidString)"
            try db.execute(
                sql: """
                INSERT INTO tombstones (
                    recordName, targetType, generation, deletedAt, tombstoneID, reason
                ) VALUES (?, 'ClipboardContent', ?, ?, ?, 'user')
                ON CONFLICT(recordName) DO UPDATE SET
                    generation = excluded.generation,
                    deletedAt = excluded.deletedAt,
                    tombstoneID = excluded.tombstoneID,
                    reason = excluded.reason,
                    uploadedAt = NULL
                """,
                arguments: [itemID.uuidString, generation, Date(), tombstoneID]
            )
            try enqueueSyncChange(
                recordType: SyncRecordType.tombstone.rawValue,
                recordName: tombstoneID,
                operation: "save",
                generation: generation,
                in: db
            )
            try enqueueSyncChange(
                recordType: SyncRecordType.clipboardContent.rawValue,
                recordName: itemID.uuidString,
                operation: "delete",
                generation: generation,
                in: db
            )
        }
    }

    private func enqueueSyncChange(
        recordType: String,
        recordName: String,
        operation: String,
        generation: Int? = nil,
        in db: Database
    ) throws {
        let resolvedGeneration = try generation ?? currentSyncGeneration(in: db)
        try db.execute(
            sql: """
            INSERT INTO sync_outbox (
                recordType, recordName, operation, generation, createdAt, attemptCount
            ) VALUES (?, ?, ?, ?, ?, 0)
            ON CONFLICT(recordType, recordName) DO UPDATE SET
                operation = excluded.operation,
                generation = excluded.generation,
                createdAt = excluded.createdAt,
                attemptCount = 0,
                lastError = NULL
            """,
            arguments: [recordType, recordName, operation, resolvedGeneration, Date()]
        )
    }

    private func enqueueSyncChangeIfSyncable(
        recordName: String,
        operation: String,
        in db: Database
    ) throws {
        guard let kindValue = try String.fetchOne(
            db,
            sql: "SELECT kind FROM clipboard_items WHERE id = ?",
            arguments: [recordName]
        ), let kind = ClipboardContentKind(rawValue: kindValue), Self.isSyncable(kind) else {
            return
        }
        try enqueueSyncChange(
            recordType: SyncRecordType.clipboardContent.rawValue,
            recordName: recordName,
            operation: operation,
            in: db
        )
    }

    private func upsertLocalDeviceReplica(
        recordName: String,
        lastCapturedAt: Date,
        lastUsedAt: Date?,
        useCount: Int,
        generation: Int,
        in db: Database
    ) throws {
        let deviceID = try deviceID(in: db)
        let replicaRecordName = "replica.\(recordName).\(deviceID)"
        try db.execute(
            sql: """
            INSERT INTO device_replicas (
                recordName, targetRecordName, deviceID, generation,
                lastCapturedAt, lastUsedAt, useCount, updatedAt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recordName) DO UPDATE SET
                targetRecordName = excluded.targetRecordName,
                generation = MAX(generation, excluded.generation),
                lastCapturedAt = MAX(lastCapturedAt, excluded.lastCapturedAt),
                lastUsedAt = CASE
                    WHEN lastUsedAt IS NULL THEN excluded.lastUsedAt
                    WHEN excluded.lastUsedAt IS NULL THEN lastUsedAt
                    ELSE MAX(lastUsedAt, excluded.lastUsedAt)
                END,
                useCount = MAX(useCount, excluded.useCount),
                updatedAt = excluded.updatedAt
            """,
            arguments: [
                replicaRecordName, recordName, deviceID, generation,
                lastCapturedAt, lastUsedAt, useCount, Date()
            ]
        )
        try enqueueSyncChange(
            recordType: SyncRecordType.deviceReplica.rawValue,
            recordName: replicaRecordName,
            operation: "save",
            generation: generation,
            in: db
        )
    }

    private func enqueueReplicaDeletions(
        targetRecordNames: [String],
        in db: Database
    ) throws {
        guard !targetRecordNames.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: targetRecordNames.count).joined(separator: ",")
        let replicaRecordNames = try String.fetchAll(
            db,
            sql: "SELECT recordName FROM device_replicas WHERE targetRecordName IN (\(placeholders))",
            arguments: StatementArguments(targetRecordNames)
        )
        for replicaRecordName in replicaRecordNames {
            try enqueueSyncChange(
                recordType: SyncRecordType.deviceReplica.rawValue,
                recordName: replicaRecordName,
                operation: "delete",
                in: db
            )
        }
    }

    private func recordAlias(
        loserRecordName: String,
        winnerRecordName: String,
        generation: Int,
        in db: Database
    ) throws {
        let date = Date()
        try db.execute(
            sql: """
            INSERT INTO sync_record_aliases (
                loserRecordName, winnerRecordName, generation, updatedAt
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT(loserRecordName) DO UPDATE SET
                winnerRecordName = CASE
                    WHEN excluded.generation >= generation THEN excluded.winnerRecordName
                    ELSE winnerRecordName
                END,
                generation = MAX(generation, excluded.generation),
                updatedAt = excluded.updatedAt
            """,
            arguments: [loserRecordName, winnerRecordName, generation, date]
        )
        try db.execute(
            sql: """
            UPDATE device_replicas SET targetRecordName = ?, updatedAt = ?
            WHERE targetRecordName = ? AND generation <= ?
            """,
            arguments: [winnerRecordName, date, loserRecordName, generation]
        )
        let hadPendingSave = (try Int.fetchOne(
            db,
            sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE recordType = ? AND recordName = ? AND operation = 'save'
            """,
            arguments: [SyncRecordType.clipboardContent.rawValue, loserRecordName]
        ) ?? 0) > 0
        try db.execute(
            sql: "DELETE FROM sync_outbox WHERE recordType = ? AND recordName = ?",
            arguments: [SyncRecordType.clipboardContent.rawValue, loserRecordName]
        )
        if hadPendingSave {
            try enqueueSyncChange(
                recordType: SyncRecordType.clipboardContent.rawValue,
                recordName: winnerRecordName,
                operation: "save",
                generation: generation,
                in: db
            )
        }
    }

    private func mergeReplicaActivity(targetRecordName: String, in db: Database) throws {
        guard let activity = try Row.fetchOne(
            db,
            sql: """
            SELECT MAX(lastCapturedAt) AS lastCapturedAt,
                   MAX(lastUsedAt) AS lastUsedAt,
                   MAX(useCount) AS useCount,
                   MAX(generation) AS generation
            FROM device_replicas WHERE targetRecordName = ?
            """,
            arguments: [targetRecordName]
        ), let lastCapturedAt: Date = activity["lastCapturedAt"] else {
            return
        }
        let lastUsedAt: Date? = activity["lastUsedAt"]
        let useCount: Int = activity["useCount"] ?? 0
        let generation: Int = activity["generation"] ?? 1
        try db.execute(
            sql: """
            UPDATE clipboard_items
            SET lastCapturedAt = MAX(lastCapturedAt, ?),
                lastUsedAt = CASE
                    WHEN lastUsedAt IS NULL THEN ?
                    WHEN ? IS NULL THEN lastUsedAt
                    ELSE MAX(lastUsedAt, ?)
                END,
                retentionAt = MAX(retentionAt, ?, COALESCE(?, retentionAt)),
                useCount = MAX(useCount, ?)
            WHERE id = ? AND syncGeneration <= ?
            """,
            arguments: [
                lastCapturedAt, lastUsedAt, lastUsedAt, lastUsedAt,
                lastCapturedAt, lastUsedAt, useCount, targetRecordName, generation
            ]
        )
    }

    private func currentSyncGeneration(in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(resetGeneration), 1) FROM sync_accounts"
        ) ?? 1
    }

    private func deviceID(in db: Database) throws -> String {
        if let data = try Data.fetchOne(
            db,
            sql: "SELECT value FROM device_overrides WHERE key = 'sync.deviceID'"
        ), let value = try? JSONDecoder().decode(String.self, from: data) {
            return value
        }
        let value = UUID().uuidString
        try db.execute(
            sql: """
            INSERT INTO device_overrides (key, value, updatedAt)
            VALUES ('sync.deviceID', ?, ?)
            ON CONFLICT(key) DO NOTHING
            """,
            arguments: [try JSONEncoder().encode(value), Date()]
        )
        return value
    }

    private static func isSyncable(_ kind: ClipboardContentKind) -> Bool {
        kind == .text || kind == .url || kind == .imageData
    }

    private func collectPayloadGarbageAfterCommit() {
        try? garbageCollector?.collect()
    }

    private static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }

    private static func uuid(from value: String) throws -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            throw ClipboardRecordError.invalidUUID(value)
        }
        return uuid
    }

    private static func likePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    private static let selectClipboardItemsSQL = """
        SELECT ci.*,
               CASE
                   WHEN po.relativePath IS NULL THEN NULL
                   WHEN ? IS NULL THEN po.relativePath
                   ELSE ? || '/' || po.relativePath
               END AS cachedFilePath
        FROM clipboard_items AS ci
        LEFT JOIN payload_objects AS po ON po.id = ci.payloadID
        """
}
