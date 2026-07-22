import Foundation
import GRDB

public struct SyncReplicaReceipt: Equatable, Sendable {
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var manifestDigest: String
    public var appliedAt: Date

    public init(
        deviceID: String,
        generation: Int,
        revision: Int64,
        manifestDigest: String,
        appliedAt: Date
    ) {
        self.deviceID = deviceID
        self.generation = generation
        self.revision = revision
        self.manifestDigest = manifestDigest
        self.appliedAt = appliedAt
    }

    public func matches(
        deviceID: String,
        generation: Int,
        revision: Int64,
        manifestDigest: String
    ) -> Bool {
        self.deviceID == deviceID
            && self.generation == generation
            && self.revision == revision
            && self.manifestDigest == manifestDigest
    }
}

public final class SyncLocalRepository: @unchecked Sendable {
    private let database: MacToolsDatabase
    private let clipboardRepository: ClipboardRepository
    private let preferenceRepository: PreferenceRepository

    public init(
        database: MacToolsDatabase,
        clipboardRepository: ClipboardRepository,
        preferenceRepository: PreferenceRepository
    ) {
        self.database = database
        self.clipboardRepository = clipboardRepository
        self.preferenceRepository = preferenceRepository
    }

    public func bindStore(_ storeID: UUID, at date: Date = Date()) throws {
        try database.writer.write { db in
            let identity = storeID.uuidString
            let previous = try String.fetchOne(
                db,
                sql: "SELECT accountHash FROM sync_accounts ORDER BY updatedAt DESC LIMIT 1"
            )
            if previous != identity {
                try db.execute(sql: "DELETE FROM sync_outbox")
                try db.execute(sql: "DELETE FROM sync_record_metadata")
                try db.execute(sql: "DELETE FROM sync_accounts")
                try db.execute(sql: "DELETE FROM file_sync_receipts")
            }
            try db.execute(
                sql: """
                INSERT INTO sync_accounts (
                    accountHash, resetGeneration, requiresBootstrap, updatedAt
                ) VALUES (?, 1, 1, ?)
                ON CONFLICT(accountHash) DO UPDATE SET updatedAt = excluded.updatedAt
                """,
                arguments: [identity, date]
            )
        }
    }

    public func currentGeneration(storeID: UUID) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT resetGeneration FROM sync_accounts WHERE accountHash = ?",
                arguments: [storeID.uuidString]
            ) ?? 1
        }
    }

    @discardableResult
    public func adoptGeneration(_ generation: Int, storeID: UUID, at date: Date = Date()) throws -> Bool {
        try database.writer.write { db in
            let current = try Int.fetchOne(
                db,
                sql: "SELECT resetGeneration FROM sync_accounts WHERE accountHash = ?",
                arguments: [storeID.uuidString]
            ) ?? 1
            guard generation > current else { return false }
            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "DELETE FROM file_sync_receipts")
            try db.execute(sql: "DELETE FROM tombstones WHERE generation < ?", arguments: [generation])
            try db.execute(
                sql: """
                UPDATE sync_accounts
                SET resetGeneration = ?, requiresBootstrap = 1, updatedAt = ?
                WHERE accountHash = ?
                """,
                arguments: [generation, date, storeID.uuidString]
            )
            return true
        }
    }

    public func advanceGeneration(storeID: UUID, at date: Date = Date()) throws -> Int {
        try database.writer.write { db in
            let next = (try Int.fetchOne(
                db,
                sql: "SELECT resetGeneration FROM sync_accounts WHERE accountHash = ?",
                arguments: [storeID.uuidString]
            ) ?? 1) + 1
            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "DELETE FROM file_sync_receipts")
            try db.execute(sql: "DELETE FROM tombstones WHERE generation < ?", arguments: [next])
            try db.execute(
                sql: """
                UPDATE sync_accounts
                SET resetGeneration = ?, requiresBootstrap = 1, updatedAt = ?
                WHERE accountHash = ?
                """,
                arguments: [next, date, storeID.uuidString]
            )
            return next
        }
    }

    public func hasPendingChanges(
        excludingClipboardRecordNames excludedRecordNames: Set<String> = []
    ) throws -> Bool {
        try database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT recordType, recordName FROM sync_outbox"
            )
            return rows.contains { row in
                let recordType: String = row["recordType"]
                let recordName: String = row["recordName"]
                return recordType != SyncRecordType.clipboardContent.rawValue
                    || !excludedRecordNames.contains(recordName)
            }
        }
    }

    public func prepareForReplacementDevice() throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM sync_outbox")
            try db.execute(sql: "DELETE FROM file_sync_receipts")
            try db.execute(
                sql: """
                UPDATE tombstones
                SET sourceDeviceID = '', sourceRevision = 0, uploadedAt = NULL
                """
            )
        }
    }

    public func preserveTombstones(
        fromRemovedDeviceID removedDeviceID: String,
        generation: Int,
        at date: Date = Date()
    ) throws {
        try database.writer.write { db in
            let tombstoneIDs = try String.fetchAll(
                db,
                sql: """
                SELECT tombstoneID
                FROM tombstones
                WHERE generation = ? AND sourceDeviceID = ?
                """,
                arguments: [generation, removedDeviceID]
            )
            guard !tombstoneIDs.isEmpty else { return }
            try db.execute(
                sql: """
                UPDATE tombstones
                SET sourceDeviceID = '', sourceRevision = 0, uploadedAt = NULL
                WHERE generation = ? AND sourceDeviceID = ?
                """,
                arguments: [generation, removedDeviceID]
            )
            for tombstoneID in tombstoneIDs {
                try db.execute(
                    sql: """
                    INSERT INTO sync_outbox (
                        recordType, recordName, operation, generation,
                        createdAt, attemptCount
                    ) VALUES (?, ?, 'save', ?, ?, 0)
                    ON CONFLICT(recordType, recordName) DO UPDATE SET
                        operation = excluded.operation,
                        generation = excluded.generation,
                        createdAt = excluded.createdAt,
                        attemptCount = 0,
                        lastError = NULL
                    """,
                    arguments: [
                        SyncRecordType.tombstone.rawValue,
                        tombstoneID,
                        generation,
                        date
                    ]
                )
            }
        }
    }

    public func exportBundle(
        deviceID: String,
        generation: Int,
        revision: Int64,
        scope: ClipboardSyncScope,
        excludingContentIDs: Set<String> = [],
        at cutoff: Date = Date()
    ) throws -> SyncExportBundle {
        var contentCache = SyncExportContentCache()
        return try exportBundle(
            deviceID: deviceID,
            generation: generation,
            revision: revision,
            scope: scope,
            excludingContentIDs: excludingContentIDs,
            contentCache: &contentCache,
            at: cutoff
        )
    }

    public func exportBundle(
        deviceID: String,
        generation: Int,
        revision: Int64,
        scope: ClipboardSyncScope,
        excludingContentIDs: Set<String> = [],
        contentCache: inout SyncExportContentCache,
        at cutoff: Date = Date()
    ) throws -> SyncExportBundle {
        let allItems = try clipboardRepository.search("", limit: Int.max)
        var records: [SyncClipboardRecord] = []
        var contentsByID: [String: SyncExportContent] = [:]
        var unavailableClipboardRecordNames: Set<String> = []

        for item in allItems where Self.isSyncable(item.kind) {
            guard scope == .allHistory || item.isFavorite || item.isPinned else {
                continue
            }
            guard let contentID = item.contentHash else {
                unavailableClipboardRecordNames.insert(item.id.uuidString)
                continue
            }
            guard !excludingContentIDs.contains(contentID) else { continue }

            let content: SyncExportContent
            if let cachedContent = contentCache.content(kind: item.kind, contentID: contentID) {
                content = cachedContent
            } else {
                switch item.kind {
                case .text, .url:
                    guard let text = item.text else {
                        unavailableClipboardRecordNames.insert(item.id.uuidString)
                        continue
                    }
                    let value = SyncTextContentObject(
                        contentID: contentID,
                        kind: item.kind,
                        text: text,
                        byteCount: Int64(Data(text.utf8).count)
                    )
                    content = SyncExportContent(
                        contentID: contentID,
                        kind: item.kind,
                        data: try SyncSnapshotCodec.encode(value)
                    )
                case .imageData:
                    guard let path = item.cachedFilePath else {
                        unavailableClipboardRecordNames.insert(item.id.uuidString)
                        continue
                    }
                    let data: Data
                    do {
                        data = try Data(
                            contentsOf: URL(fileURLWithPath: path),
                            options: [.mappedIfSafe]
                        )
                    } catch {
                        unavailableClipboardRecordNames.insert(item.id.uuidString)
                        continue
                    }
                    guard Int64(data.count) <= SyncRetentionPolicy.maximumImageBytes else {
                        continue
                    }
                    guard ClipboardContentHasher.sha256String(for: data) == contentID else {
                        unavailableClipboardRecordNames.insert(item.id.uuidString)
                        continue
                    }
                    content = SyncExportContent(contentID: contentID, kind: item.kind, data: data)
                default:
                    continue
                }
                contentCache.store(content)
            }

            contentsByID[contentID] = content
            records.append(
                SyncClipboardRecord(
                    recordName: item.id.uuidString,
                    contentID: contentID,
                    kind: item.kind,
                    displayTitle: item.displayTitle,
                    searchableText: item.searchableText,
                    sourceApp: item.sourceApp,
                    createdAt: item.createdAt,
                    lastCapturedAt: item.lastCapturedAt,
                    lastUsedAt: item.lastUsedAt,
                    retentionAt: item.retentionAt,
                    useCount: item.useCount,
                    isPinned: item.isPinned,
                    isFavorite: item.isFavorite,
                    favoriteClock: item.favoriteClock,
                    pinnedClock: item.pinnedClock
                )
            )
        }
        records.sort { $0.recordName < $1.recordName }

        let domains = try PreferenceRepository.accountDomains.compactMap { domain in
            try preferenceRepository.domainDocument(domain).map {
                SyncPreferenceDomainRecord(
                    domain: $0.domain,
                    value: $0.value,
                    clocks: $0.clocks,
                    updatedAt: $0.updatedAt
                )
            }
        }.sorted { $0.domain < $1.domain }

        let tombstones = try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE tombstones
                SET sourceDeviceID = ?, sourceRevision = ?
                WHERE generation = ? AND sourceDeviceID = ''
                """,
                arguments: [deviceID, revision, generation]
            )
            return try Row.fetchAll(
                db,
                sql: """
                SELECT recordName, targetType, generation, deletedAt,
                       tombstoneID, reason, sourceDeviceID, sourceRevision
                FROM tombstones
                WHERE generation = ? AND sourceDeviceID = ?
                ORDER BY tombstoneID ASC
                """,
                arguments: [generation, deviceID]
            ).map { row in
                SyncTombstoneRecord(
                    tombstoneID: row["tombstoneID"],
                    targetRecordName: row["recordName"],
                    targetType: row["targetType"],
                    generation: row["generation"],
                    deletedAt: row["deletedAt"],
                    reason: row["reason"],
                    sourceDeviceID: row["sourceDeviceID"],
                    sourceRevision: row["sourceRevision"]
                )
            }
        }

        return SyncExportBundle(
            clipboard: SyncClipboardSnapshot(
                deviceID: deviceID,
                generation: generation,
                revision: revision,
                records: records
            ),
            preferences: SyncPreferencesSnapshot(
                deviceID: deviceID,
                generation: generation,
                revision: revision,
                domains: domains
            ),
            tombstones: SyncTombstoneSnapshot(
                deviceID: deviceID,
                generation: generation,
                revision: revision,
                records: tombstones
            ),
            contents: contentsByID.values.sorted { $0.contentID < $1.contentID },
            outboxCutoff: cutoff,
            unavailableClipboardRecordNames: unavailableClipboardRecordNames
        )
    }

    public func apply(
        clipboard snapshot: SyncClipboardSnapshot,
        contents: [String: Data],
        payloadStore: PayloadStore,
        historyLimit: Int
    ) throws {
        let deletedRecordNames = try tombstonedRecordNames(generation: snapshot.generation)
        for record in snapshot.records where !deletedRecordNames.contains(record.recordName) {
            guard let data = contents[record.contentID] else { continue }
            let payload: PayloadObjectDescriptor?
            let text: String?
            switch record.kind {
            case .text, .url:
                let object = try SyncSnapshotCodec.decode(SyncTextContentObject.self, from: data)
                guard object.contentID == record.contentID,
                      object.kind == record.kind,
                      ClipboardContentHasher.sha256String(
                          for: Data("text:\(object.text)".utf8)
                      ) == record.contentID else {
                    continue
                }
                payload = nil
                text = object.text
            case .imageData:
                guard Int64(data.count) <= SyncRetentionPolicy.maximumImageBytes,
                      ClipboardContentHasher.sha256String(for: data) == record.contentID else {
                    continue
                }
                payload = try payloadStore.storePNG(data)
                text = nil
            default:
                continue
            }
            guard let id = UUID(uuidString: record.recordName) else { continue }
            let item = ClipboardItem(
                id: id,
                kind: record.kind,
                displayTitle: record.displayTitle,
                searchableText: record.searchableText,
                text: text,
                originalPath: nil,
                cachedFilePath: nil,
                thumbnailPath: nil,
                sourceApp: record.sourceApp,
                contentHash: record.contentID,
                createdAt: record.createdAt,
                lastUsedAt: record.lastUsedAt,
                useCount: record.useCount,
                isPinned: record.isPinned,
                isFavorite: record.isFavorite,
                lastCapturedAt: record.lastCapturedAt,
                retentionAt: record.retentionAt,
                payloadID: payload?.id,
                syncGeneration: snapshot.generation,
                favoriteClock: record.favoriteClock,
                pinnedClock: record.pinnedClock
            )
            _ = try clipboardRepository.upsert(
                item,
                payload: payload,
                historyLimit: historyLimit,
                enqueuesSyncChange: false,
                deterministicallyMergesRecordNames: true
            )
        }
    }

    public func apply(tombstones snapshot: SyncTombstoneSnapshot) throws {
        for record in snapshot.records {
            var resolvedTargetRecordName = record.targetRecordName
            try database.writer.write { db in
                resolvedTargetRecordName = try resolveAlias(
                    recordName: record.targetRecordName,
                    generation: record.generation,
                    in: db
                )
                for targetRecordName in Set([record.targetRecordName, resolvedTargetRecordName]) {
                    let tombstoneID = targetRecordName == record.targetRecordName
                        ? record.tombstoneID
                        : "local.alias.\(record.tombstoneID).\(targetRecordName)"
                    try db.execute(
                        sql: """
                        INSERT INTO tombstones (
                            recordName, targetType, generation, deletedAt, uploadedAt,
                            tombstoneID, reason, sourceDeviceID, sourceRevision
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(recordName) DO UPDATE SET
                            targetType = CASE WHEN excluded.generation >= generation THEN excluded.targetType ELSE targetType END,
                            generation = MAX(generation, excluded.generation),
                            deletedAt = CASE WHEN excluded.generation >= generation THEN excluded.deletedAt ELSE deletedAt END,
                            uploadedAt = CASE WHEN excluded.generation >= generation THEN excluded.uploadedAt ELSE uploadedAt END,
                            tombstoneID = CASE WHEN excluded.generation >= generation THEN excluded.tombstoneID ELSE tombstoneID END,
                            reason = CASE WHEN excluded.generation >= generation THEN excluded.reason ELSE reason END,
                            sourceDeviceID = CASE WHEN excluded.generation >= generation THEN excluded.sourceDeviceID ELSE sourceDeviceID END,
                            sourceRevision = CASE WHEN excluded.generation >= generation THEN excluded.sourceRevision ELSE sourceRevision END
                        """,
                        arguments: [
                            targetRecordName, record.targetType, record.generation,
                            record.deletedAt, record.deletedAt, tombstoneID, record.reason,
                            record.sourceDeviceID, record.sourceRevision
                        ]
                    )
                }
            }
            guard let id = UUID(uuidString: resolvedTargetRecordName) else { continue }
            try clipboardRepository.delete(id: id, createsTombstone: false)
        }
    }

    public func tombstonedRecordNames(generation: Int) throws -> Set<String> {
        try database.writer.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT recordName FROM tombstones WHERE generation = ?",
                arguments: [generation]
            ))
        }
    }

    @discardableResult
    public func compactAcknowledgedTombstones(
        activeManifests: [SyncReplicaManifest],
        localDeviceID: String,
        generation: Int
    ) throws -> Set<String> {
        _ = localDeviceID
        let rows = try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT tombstoneID, sourceDeviceID, sourceRevision
                FROM tombstones
                WHERE generation = ? AND sourceDeviceID != '' AND sourceRevision > 0
                """,
                arguments: [generation]
            )
        }
        let acknowledged = Set(rows.compactMap { row -> String? in
            let sourceDeviceID: String = row["sourceDeviceID"]
            let sourceRevision: Int64 = row["sourceRevision"]
            guard activeManifests.contains(where: {
                $0.deviceID == sourceDeviceID && $0.revision >= sourceRevision
            }) else {
                return nil
            }
            let isSeenByAll = activeManifests.allSatisfy { manifest in
                if manifest.deviceID == sourceDeviceID {
                    return manifest.revision >= sourceRevision
                }
                return (manifest.seenRevisions[sourceDeviceID] ?? 0) >= sourceRevision
            }
            return isSeenByAll ? row["tombstoneID"] : nil
        })
        guard !acknowledged.isEmpty else { return [] }
        try database.writer.write { db in
            let placeholders = Array(repeating: "?", count: acknowledged.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM tombstones WHERE tombstoneID IN (\(placeholders))",
                arguments: StatementArguments(acknowledged.sorted())
            )
        }
        return acknowledged
    }

    @discardableResult
    public func apply(preferences snapshot: SyncPreferencesSnapshot) throws -> AppSettings? {
        var lastSettings: AppSettings?
        for record in snapshot.domains {
            lastSettings = try preferenceRepository.applyRemoteDomain(
                PreferenceDomainDocument(
                    domain: record.domain,
                    value: record.value,
                    clocks: record.clocks,
                    updatedAt: record.updatedAt
                )
            )
        }
        return lastSettings
    }

    public func acknowledgeSnapshot(
        upTo cutoff: Date,
        excludingClipboardRecordNames excludedRecordNames: Set<String> = [],
        uploadedContentIDs: Set<String> = [],
        at date: Date = Date()
    ) throws {
        try database.writer.write { db in
            let acknowledgedOutboxIDs = try Row.fetchAll(
                db,
                sql: """
                SELECT id, recordType, recordName
                FROM sync_outbox
                WHERE createdAt <= ?
                """,
                arguments: [cutoff]
            ).compactMap { row -> Int64? in
                let recordType: String = row["recordType"]
                let recordName: String = row["recordName"]
                guard recordType != SyncRecordType.clipboardContent.rawValue
                        || !excludedRecordNames.contains(recordName) else {
                    return nil
                }
                return row["id"]
            }
            if !acknowledgedOutboxIDs.isEmpty {
                let placeholders = Array(
                    repeating: "?",
                    count: acknowledgedOutboxIDs.count
                ).joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM sync_outbox WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(acknowledgedOutboxIDs)
                )
            }
            try db.execute(
                sql: "UPDATE tombstones SET uploadedAt = ? WHERE deletedAt <= ?",
                arguments: [date, cutoff]
            )
            if !uploadedContentIDs.isEmpty {
                let values = uploadedContentIDs.sorted()
                let placeholders = Array(repeating: "?", count: values.count).joined(separator: ",")
                try db.execute(
                    sql: """
                    UPDATE payload_objects
                    SET cloudState = 'uploaded'
                    WHERE localState = 'available'
                      AND contentHash IN (\(placeholders))
                    """,
                    arguments: StatementArguments(values)
                )
            }
        }
    }

    public func recordReceipt(_ receipt: SyncReplicaReceipt) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO file_sync_receipts (
                    deviceID, generation, revision, manifestDigest, appliedAt
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(deviceID) DO UPDATE SET
                    generation = excluded.generation,
                    revision = excluded.revision,
                    manifestDigest = excluded.manifestDigest,
                    appliedAt = excluded.appliedAt
                """,
                arguments: [
                    receipt.deviceID, receipt.generation, receipt.revision,
                    receipt.manifestDigest, receipt.appliedAt
                ]
            )
        }
    }

    public func receipts() throws -> [SyncReplicaReceipt] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM file_sync_receipts ORDER BY deviceID"
            ).map { row in
                SyncReplicaReceipt(
                    deviceID: row["deviceID"],
                    generation: row["generation"],
                    revision: row["revision"],
                    manifestDigest: row["manifestDigest"],
                    appliedAt: row["appliedAt"]
                )
            }
        }
    }

    public func garbageCollectionCandidates(
        allContentIDs: Set<String>,
        referencedContentIDs: Set<String>,
        stableFor interval: TimeInterval = 24 * 60 * 60,
        now: Date = Date()
    ) throws -> Set<String> {
        let unreferenced = allContentIDs.subtracting(referencedContentIDs)
        return try database.writer.write { db in
            if allContentIDs.isEmpty {
                try db.execute(sql: "DELETE FROM sync_object_gc_observations")
                return []
            }
            let placeholders = Array(repeating: "?", count: allContentIDs.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM sync_object_gc_observations WHERE contentID NOT IN (\(placeholders))",
                arguments: StatementArguments(allContentIDs.sorted())
            )
            if !referencedContentIDs.isEmpty {
                let referencedPlaceholders = Array(
                    repeating: "?",
                    count: referencedContentIDs.count
                ).joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM sync_object_gc_observations WHERE contentID IN (\(referencedPlaceholders))",
                    arguments: StatementArguments(referencedContentIDs.sorted())
                )
            }
            for contentID in unreferenced {
                try db.execute(
                    sql: """
                    INSERT INTO sync_object_gc_observations (contentID, firstUnreferencedAt)
                    VALUES (?, ?)
                    ON CONFLICT(contentID) DO NOTHING
                    """,
                    arguments: [contentID, now]
                )
            }
            return Set(try String.fetchAll(
                db,
                sql: """
                SELECT contentID FROM sync_object_gc_observations
                WHERE firstUnreferencedAt <= ?
                """,
                arguments: [now.addingTimeInterval(-max(0, interval))]
            ))
        }
    }

    public func acknowledgeGarbageCollected(contentIDs: Set<String>) throws {
        guard !contentIDs.isEmpty else { return }
        try database.writer.write { db in
            let placeholders = Array(repeating: "?", count: contentIDs.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM sync_object_gc_observations WHERE contentID IN (\(placeholders))",
                arguments: StatementArguments(contentIDs.sorted())
            )
        }
    }

    private static func isSyncable(_ kind: ClipboardContentKind) -> Bool {
        kind == .text || kind == .url || kind == .imageData
    }

    private func resolveAlias(
        recordName: String,
        generation: Int,
        in db: Database
    ) throws -> String {
        var current = recordName
        var visited = Set<String>()
        while visited.insert(current).inserted,
              let next = try String.fetchOne(
                  db,
                  sql: """
                  SELECT winnerRecordName FROM sync_record_aliases
                  WHERE loserRecordName = ? AND generation = ?
                  """,
                  arguments: [current, generation]
              ), next != current {
            current = next
        }
        return current
    }
}
