// 本地发布台账为 iCloud manifest 的跨进程失败提供持久证据。
// 缺少证明时只保留快照，不根据年龄或一次目录观察推断可删除。

import Foundation
import GRDB

public enum SyncSnapshotPublicationState: String, Equatable, Hashable, Sendable {
    case prepared
    case publicationUncertain
    case published
    case superseded
    /// 快照目录已物理回收，但仍保留迟到 manifest 的作废证据。
    case reclaimed
}

public struct SyncSnapshotPublicationIdentity: Equatable, Hashable, Sendable {
    public var storeID: UUID
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var snapshotDirectory: String

    public init(
        storeID: UUID,
        deviceID: String,
        generation: Int,
        revision: Int64,
        snapshotDirectory: String
    ) {
        self.storeID = storeID
        self.deviceID = deviceID
        self.generation = generation
        self.revision = revision
        self.snapshotDirectory = snapshotDirectory
    }
}

public struct SyncSnapshotPublicationRecord: Equatable, Sendable {
    public var storeID: UUID
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var snapshotDirectory: String
    public var snapshotDigests: SyncSnapshotDigests
    public var manifestDigest: String
    public var state: SyncSnapshotPublicationState
    public var supersededByRevision: Int64?
    public var updatedAt: Date

    public var identity: SyncSnapshotPublicationIdentity {
        SyncSnapshotPublicationIdentity(
            storeID: storeID,
            deviceID: deviceID,
            generation: generation,
            revision: revision,
            snapshotDirectory: snapshotDirectory
        )
    }

    public init(
        storeID: UUID,
        deviceID: String,
        generation: Int,
        revision: Int64,
        snapshotDirectory: String,
        snapshotDigests: SyncSnapshotDigests,
        manifestDigest: String,
        state: SyncSnapshotPublicationState,
        supersededByRevision: Int64?,
        updatedAt: Date
    ) {
        self.storeID = storeID
        self.deviceID = deviceID
        self.generation = generation
        self.revision = revision
        self.snapshotDirectory = snapshotDirectory
        self.snapshotDigests = snapshotDigests
        self.manifestDigest = manifestDigest
        self.state = state
        self.supersededByRevision = supersededByRevision
        self.updatedAt = updatedAt
    }
}

public enum SyncSnapshotPublicationLedgerError: Error, Equatable, Sendable {
    case missingRecord
    case invalidTransition(from: SyncSnapshotPublicationState, to: SyncSnapshotPublicationState)
}

public final class SyncSnapshotPublicationLedger: @unchecked Sendable {
    private let database: MacToolsDatabase

    public init(database: MacToolsDatabase) {
        self.database = database
    }

    public func recordPrepared(_ record: SyncSnapshotPublicationRecord) throws {
        try database.writer.write { db in
            try Self.recordPrepared(record, in: db)
        }
    }

    public func markPublicationUncertain(
        _ identity: SyncSnapshotPublicationIdentity,
        at date: Date = Date()
    ) throws {
        try database.writer.write { db in
            try Self.transition(
                identity,
                allowed: [.prepared, .publicationUncertain],
                to: .publicationUncertain,
                supersededByRevision: nil,
                manifestDigest: nil,
                at: date,
                in: db
            )
        }
    }

    public func markPublished(
        _ identity: SyncSnapshotPublicationIdentity,
        manifestDigest: String,
        at date: Date = Date()
    ) throws {
        try database.writer.write { db in
            try Self.markPublished(
                identity,
                manifestDigest: manifestDigest,
                at: date,
                in: db
            )
        }
    }

    public func record(
        for identity: SyncSnapshotPublicationIdentity
    ) throws -> SyncSnapshotPublicationRecord? {
        try database.writer.read { db in
            try Self.fetch(identity, in: db)
        }
    }

    public func cleanupCandidates(
        storeID: UUID,
        deviceID: String,
        generation: Int,
        protectedDirectories: Set<String>,
        limit: Int = 256
    ) throws -> [SyncSnapshotPublicationRecord] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM sync_snapshot_publications
                WHERE storeID = ? AND deviceID = ? AND generation = ?
                  AND state IN (?, ?)
                ORDER BY revision ASC, snapshotDirectory ASC
                LIMIT ?
                """,
                arguments: [
                    storeID.uuidString, deviceID, generation,
                    SyncSnapshotPublicationState.prepared.rawValue,
                    SyncSnapshotPublicationState.superseded.rawValue,
                    max(0, limit + protectedDirectories.count)
                ]
            ).compactMap(Self.record(from:)).filter {
                !protectedDirectories.contains($0.snapshotDirectory)
            }.prefix(max(0, limit)).map { $0 }
        }
    }

    public func supersededRecord(
        storeID: UUID,
        deviceID: String,
        generation: Int,
        revision: Int64,
        snapshotDirectory: String,
        snapshotDigests: SyncSnapshotDigests,
        manifestDigest: String
    ) throws -> SyncSnapshotPublicationRecord? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT * FROM sync_snapshot_publications
                WHERE storeID = ? AND deviceID = ? AND generation = ? AND revision = ?
                  AND snapshotDirectory = ? AND clipboardDigest = ? AND preferencesDigest = ?
                  AND tombstonesDigest = ? AND manifestDigest = ? AND state IN (?, ?)
                """,
                arguments: [
                    storeID.uuidString, deviceID, generation, revision, snapshotDirectory,
                    snapshotDigests.clipboard, snapshotDigests.preferences,
                    snapshotDigests.tombstones, manifestDigest,
                    SyncSnapshotPublicationState.superseded.rawValue,
                    SyncSnapshotPublicationState.reclaimed.rawValue
                ]
            ) else { return nil }
            return Self.record(from: row)
        }
    }

    public func removeRecord(_ identity: SyncSnapshotPublicationIdentity) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM sync_snapshot_publications
                WHERE storeID = ? AND deviceID = ? AND generation = ? AND revision = ?
                  AND snapshotDirectory = ?
                """,
                arguments: Self.arguments(for: identity)
            )
        }
    }

    public func markReclaimed(
        _ identity: SyncSnapshotPublicationIdentity,
        at date: Date = Date()
    ) throws {
        try database.writer.write { db in
            try Self.transition(
                identity,
                allowed: [.superseded, .reclaimed],
                to: .reclaimed,
                supersededByRevision: try Self.fetch(identity, in: db)?.supersededByRevision,
                manifestDigest: nil,
                at: date,
                in: db
            )
        }
    }

    static func recordPrepared(
        _ record: SyncSnapshotPublicationRecord,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO sync_snapshot_publications (
                storeID, deviceID, generation, revision, snapshotDirectory,
                clipboardDigest, preferencesDigest, tombstonesDigest, manifestDigest,
                state, supersededByRevision, updatedAt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
            ON CONFLICT(storeID, deviceID, generation, revision, snapshotDirectory) DO UPDATE SET
                clipboardDigest = CASE
                    WHEN sync_snapshot_publications.state = 'prepared' THEN excluded.clipboardDigest
                    ELSE sync_snapshot_publications.clipboardDigest
                END,
                preferencesDigest = CASE
                    WHEN sync_snapshot_publications.state = 'prepared' THEN excluded.preferencesDigest
                    ELSE sync_snapshot_publications.preferencesDigest
                END,
                tombstonesDigest = CASE
                    WHEN sync_snapshot_publications.state = 'prepared' THEN excluded.tombstonesDigest
                    ELSE sync_snapshot_publications.tombstonesDigest
                END,
                manifestDigest = CASE
                    WHEN sync_snapshot_publications.state = 'prepared' THEN excluded.manifestDigest
                    ELSE sync_snapshot_publications.manifestDigest
                END,
                updatedAt = CASE
                    WHEN sync_snapshot_publications.state = 'prepared' THEN excluded.updatedAt
                    ELSE sync_snapshot_publications.updatedAt
                END
            """,
            arguments: [
                record.storeID.uuidString, record.deviceID, record.generation, record.revision,
                record.snapshotDirectory, record.snapshotDigests.clipboard,
                record.snapshotDigests.preferences, record.snapshotDigests.tombstones,
                record.manifestDigest, SyncSnapshotPublicationState.prepared.rawValue,
                record.updatedAt
            ]
        )
    }

    static func markPublished(
        _ identity: SyncSnapshotPublicationIdentity,
        manifestDigest: String,
        at date: Date,
        in db: Database
    ) throws {
        try transition(
            identity,
            allowed: [.prepared, .publicationUncertain, .published],
            to: .published,
            supersededByRevision: nil,
            manifestDigest: manifestDigest,
            at: date,
            in: db
        )
        try db.execute(
            sql: """
            UPDATE sync_snapshot_publications
            SET state = ?, supersededByRevision = ?, updatedAt = ?
            WHERE storeID = ? AND deviceID = ? AND generation = ? AND revision < ?
              AND state IN (?, ?, ?)
            """,
            arguments: [
                SyncSnapshotPublicationState.superseded.rawValue, identity.revision, date,
                identity.storeID.uuidString, identity.deviceID, identity.generation,
                identity.revision, SyncSnapshotPublicationState.prepared.rawValue,
                SyncSnapshotPublicationState.publicationUncertain.rawValue,
                SyncSnapshotPublicationState.published.rawValue
            ]
        )
    }

    private static func transition(
        _ identity: SyncSnapshotPublicationIdentity,
        allowed: Set<SyncSnapshotPublicationState>,
        to state: SyncSnapshotPublicationState,
        supersededByRevision: Int64?,
        manifestDigest: String?,
        at date: Date,
        in db: Database
    ) throws {
        guard let existing = try fetch(identity, in: db) else {
            throw SyncSnapshotPublicationLedgerError.missingRecord
        }
        guard allowed.contains(existing.state) else {
            throw SyncSnapshotPublicationLedgerError.invalidTransition(from: existing.state, to: state)
        }
        try db.execute(
            sql: """
            UPDATE sync_snapshot_publications
            SET state = ?, supersededByRevision = ?, manifestDigest = COALESCE(?, manifestDigest),
                updatedAt = ?
            WHERE storeID = ? AND deviceID = ? AND generation = ? AND revision = ?
              AND snapshotDirectory = ?
            """,
            arguments: [
                state.rawValue, supersededByRevision, manifestDigest, date
            ] + arguments(for: identity)
        )
    }

    private static func fetch(
        _ identity: SyncSnapshotPublicationIdentity,
        in db: Database
    ) throws -> SyncSnapshotPublicationRecord? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT * FROM sync_snapshot_publications
            WHERE storeID = ? AND deviceID = ? AND generation = ? AND revision = ?
              AND snapshotDirectory = ?
            """,
            arguments: arguments(for: identity)
        ) else { return nil }
        return record(from: row)
    }

    private static func arguments(
        for identity: SyncSnapshotPublicationIdentity
    ) -> StatementArguments {
        [
            identity.storeID.uuidString, identity.deviceID, identity.generation,
            identity.revision, identity.snapshotDirectory
        ]
    }

    private static func record(from row: Row) -> SyncSnapshotPublicationRecord? {
        guard let storeID = UUID(uuidString: row["storeID"]),
              let state = SyncSnapshotPublicationState(rawValue: row["state"]) else {
            return nil
        }
        return SyncSnapshotPublicationRecord(
            storeID: storeID,
            deviceID: row["deviceID"],
            generation: row["generation"],
            revision: row["revision"],
            snapshotDirectory: row["snapshotDirectory"],
            snapshotDigests: SyncSnapshotDigests(
                clipboard: row["clipboardDigest"],
                preferences: row["preferencesDigest"],
                tombstones: row["tombstonesDigest"]
            ),
            manifestDigest: row["manifestDigest"],
            state: state,
            supersededByRevision: row["supersededByRevision"],
            updatedAt: row["updatedAt"]
        )
    }
}
