import Foundation
import GRDB
import XCTest
@testable import MacToolsCore

final class SyncSnapshotPublicationLedgerTests: XCTestCase {
    func testMigrationCreatesEmptyPublicationLedger() throws {
        let database = try MacToolsDatabase.inMemory()

        let tableExists = try database.writer.read { db in
            try db.tableExists("sync_snapshot_publications")
        }
        let count = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_snapshot_publications")
        }

        XCTAssertTrue(tableExists)
        XCTAssertEqual(count, 0)
    }

    func testV11MigrationPreservesExistingSyncAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Clipboard.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        var database: MacToolsDatabase? = try MacToolsDatabase.at(url)
        try bindStore(in: try XCTUnwrap(database))
        try database?.writer.write { db in
            try db.drop(table: "sync_snapshot_publications")
            try db.execute(
                sql: "DELETE FROM grdb_migrations WHERE identifier = 'addSnapshotPublicationLedgerV11'"
            )
        }
        database = nil

        let migrated = try MacToolsDatabase.at(url)
        let account = try migrated.writer.read { db in
            try String.fetchOne(db, sql: "SELECT accountHash FROM sync_accounts")
        }

        XCTAssertEqual(account, "00000000-0000-0000-0000-000000000001")
        XCTAssertTrue(try migrated.writer.read { try $0.tableExists("sync_snapshot_publications") })
    }

    func testPublishedRevisionSupersedesEarlierUncertainRevision() throws {
        let database = try MacToolsDatabase.inMemory()
        try bindStore(in: database)
        let ledger = SyncSnapshotPublicationLedger(database: database)
        let first = record(revision: 1, state: .prepared)
        let second = record(revision: 2, state: .prepared)
        try ledger.recordPrepared(first)
        try ledger.markPublicationUncertain(first.identity)

        XCTAssertEqual(try ledger.record(for: first.identity)?.state, .publicationUncertain)

        try ledger.recordPrepared(second)
        try ledger.markPublished(second.identity, manifestDigest: second.manifestDigest)

        XCTAssertEqual(try ledger.record(for: second.identity)?.state, .published)
        XCTAssertEqual(try ledger.record(for: first.identity)?.state, .superseded)
        XCTAssertEqual(try ledger.record(for: first.identity)?.supersededByRevision, 2)
    }

    func testRetryDoesNotOverwriteUncertainPublicationEvidence() throws {
        let database = try MacToolsDatabase.inMemory()
        try bindStore(in: database)
        let ledger = SyncSnapshotPublicationLedger(database: database)
        let original = record(revision: 1, state: .prepared)
        try ledger.recordPrepared(original)
        try ledger.markPublicationUncertain(original.identity, at: original.updatedAt)
        var retried = original
        retried.manifestDigest = "new-draft-manifest"
        retried.updatedAt = original.updatedAt.addingTimeInterval(60)

        try ledger.recordPrepared(retried)

        XCTAssertEqual(try ledger.record(for: original.identity), {
            var expected = original
            expected.state = .publicationUncertain
            return expected
        }())
    }

    func testUncertainAndUntrackedDirectoriesAreNeverCleanupCandidates() throws {
        let database = try MacToolsDatabase.inMemory()
        try bindStore(in: database)
        let ledger = SyncSnapshotPublicationLedger(database: database)
        let prepared = record(revision: 1, state: .prepared)
        let uncertain = record(revision: 2, state: .prepared)
        try ledger.recordPrepared(prepared)
        try ledger.recordPrepared(uncertain)
        try ledger.markPublicationUncertain(uncertain.identity)

        let candidates = try ledger.cleanupCandidates(
            storeID: prepared.storeID,
            deviceID: prepared.deviceID,
            generation: prepared.generation,
            protectedDirectories: []
        )

        XCTAssertEqual(candidates.map(\.snapshotDirectory), [prepared.snapshotDirectory])
        XCTAssertFalse(candidates.map(\.snapshotDirectory).contains("legacy-uuid-without-ledger"))
    }

    func testSupersededLookupRequiresEveryManifestFieldToMatch() throws {
        let database = try MacToolsDatabase.inMemory()
        try bindStore(in: database)
        let ledger = SyncSnapshotPublicationLedger(database: database)
        let first = record(revision: 1, state: .prepared)
        let second = record(revision: 2, state: .prepared)
        try ledger.recordPrepared(first)
        try ledger.markPublicationUncertain(first.identity)
        try ledger.recordPrepared(second)
        try ledger.markPublished(second.identity, manifestDigest: second.manifestDigest)

        XCTAssertEqual(
            try ledger.supersededRecord(
                storeID: first.storeID,
                deviceID: first.deviceID,
                generation: first.generation,
                revision: first.revision,
                snapshotDirectory: first.snapshotDirectory,
                snapshotDigests: first.snapshotDigests,
                manifestDigest: first.manifestDigest
            )?.identity,
            first.identity
        )
        var mismatched = first.snapshotDigests
        mismatched.clipboard = "different"
        XCTAssertNil(try ledger.supersededRecord(
            storeID: first.storeID,
            deviceID: first.deviceID,
            generation: first.generation,
            revision: first.revision,
            snapshotDirectory: first.snapshotDirectory,
            snapshotDigests: mismatched,
            manifestDigest: first.manifestDigest
        ))

        try ledger.markReclaimed(first.identity)
        XCTAssertEqual(try ledger.record(for: first.identity)?.state, .reclaimed)
        XCTAssertEqual(
            try ledger.supersededRecord(
                storeID: first.storeID,
                deviceID: first.deviceID,
                generation: first.generation,
                revision: first.revision,
                snapshotDirectory: first.snapshotDirectory,
                snapshotDigests: first.snapshotDigests,
                manifestDigest: first.manifestDigest
            )?.identity,
            first.identity
        )
        XCTAssertTrue(
            try ledger.cleanupCandidates(
                storeID: first.storeID,
                deviceID: first.deviceID,
                generation: first.generation,
                protectedDirectories: []
            ).isEmpty
        )
    }

    private func record(
        revision: Int64,
        state: SyncSnapshotPublicationState
    ) -> SyncSnapshotPublicationRecord {
        let digests = SyncSnapshotDigests(
            clipboard: "clipboard-\(revision)",
            preferences: "preferences-\(revision)",
            tombstones: "tombstones-\(revision)"
        )
        return SyncSnapshotPublicationRecord(
            storeID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            deviceID: "device-a",
            generation: 1,
            revision: revision,
            snapshotDirectory: "g1-r\(revision)-digest",
            snapshotDigests: digests,
            manifestDigest: "manifest-\(revision)",
            state: state,
            supersededByRevision: nil,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(revision))
        )
    }

    private func bindStore(in database: MacToolsDatabase) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO sync_accounts (
                    accountHash, resetGeneration, requiresBootstrap, updatedAt
                ) VALUES (?, 1, 1, ?)
                """,
                arguments: [
                    "00000000-0000-0000-0000-000000000001",
                    Date(timeIntervalSince1970: 0)
                ]
            )
        }
    }
}
