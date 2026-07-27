import Foundation
import XCTest
@testable import MacToolsCore

final class CredentialSyncEngineTests: XCTestCase {
    private let codec = CredentialEnvelopeCodec()
    private let deviceA = "00000000-0000-0000-0000-00000000000A"
    private let deviceB = "00000000-0000-0000-0000-00000000000B"

    func testLocalWinnerIsPublishedToCurrentDeviceReplica() throws {
        let fixture = makeFixture()
        let local = try fixture.localStore.update(
            value: "local-placeholder",
            for: .bailianAPIKey,
            deviceID: deviceA
        )

        let result = try CredentialSyncEngine(localStore: fixture.localStore).synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceA,
            removedDeviceIDs: []
        )

        XCTAssertEqual(result.winner, local)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.didWriteReplica)
        XCTAssertEqual(
            try CredentialReplicaStore(rootURL: fixture.syncRoot)
                .scan(excluding: []).replicas,
            [CredentialReplica(deviceID: deviceA, envelope: local.envelope)]
        )
    }

    func testRemoteWinnerRepairsLocalAndIsRepublishedByCurrentDevice() throws {
        let fixture = makeFixture()
        let remote = try codec.seal(
            value: "remote-placeholder",
            for: .bailianAPIKey,
            clock: ClipboardFieldClock(counter: 4, deviceID: deviceA),
            updatedAt: Date(timeIntervalSince1970: 4)
        )
        try CredentialReplicaStore(rootURL: fixture.syncRoot)
            .write(remote, deviceID: deviceA)

        let result = try CredentialSyncEngine(localStore: fixture.localStore).synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceB,
            removedDeviceIDs: []
        )

        XCTAssertEqual(result.winner?.record.value, "remote-placeholder")
        XCTAssertTrue(result.didWriteReplica)
        XCTAssertEqual(
            try fixture.localStore.readEnvelope(for: .bailianAPIKey),
            remote
        )
        XCTAssertTrue(try fixture.localStore.isMigrationComplete())
        XCTAssertEqual(
            try CredentialReplicaStore(rootURL: fixture.syncRoot)
                .scan(excluding: []).replicas.map(\.deviceID),
            [deviceA, deviceB]
        )
    }

    func testHealthyReplicaWinsWhileCorruptedPeerIsReported() throws {
        let fixture = makeFixture()
        let remote = try codec.seal(
            value: "healthy-placeholder",
            for: .bailianAPIKey,
            clock: ClipboardFieldClock(counter: 2, deviceID: deviceA),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try CredentialReplicaStore(rootURL: fixture.syncRoot)
            .write(remote, deviceID: deviceA)
        let replicasDirectory = fixture.syncRoot.appendingPathComponent(
            "credentials/replicas",
            isDirectory: true
        )
        try Data("not-json".utf8).write(
            to: replicasDirectory.appendingPathComponent("\(deviceB).v1.json")
        )

        let result = try CredentialSyncEngine(localStore: fixture.localStore).synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceA,
            removedDeviceIDs: []
        )

        XCTAssertEqual(result.winner?.record.value, "healthy-placeholder")
        XCTAssertFalse(result.didWriteReplica)
        XCTAssertEqual(result.failures, [
            CredentialReplicaFailure(
                deviceID: deviceB,
                error: .unreadableReplica(deviceB)
            )
        ])
    }

    func testValidRemoteRepairsCorruptedLocalEnvelope() throws {
        let fixture = makeFixture()
        let remote = try codec.seal(
            value: "repair-placeholder",
            for: .bailianAPIKey,
            clock: ClipboardFieldClock(counter: 3, deviceID: deviceA),
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        try CredentialReplicaStore(rootURL: fixture.syncRoot)
            .write(remote, deviceID: deviceA)
        try FileManager.default.createDirectory(
            at: fixture.paths.credentialsDirectory,
            withIntermediateDirectories: true
        )
        try Data("corrupt".utf8).write(to: fixture.paths.bailianCredentialURL)

        let result = try CredentialSyncEngine(localStore: fixture.localStore).synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceB,
            removedDeviceIDs: []
        )

        XCTAssertEqual(result.winner?.record.value, "repair-placeholder")
        XCTAssertTrue(result.didWriteReplica)
        XCTAssertEqual(
            try fixture.localStore.readEnvelope(for: .bailianAPIKey),
            remote
        )
    }

    func testNoLocalOrRemoteRecordReturnsNoWinner() throws {
        let fixture = makeFixture()

        let result = try CredentialSyncEngine(localStore: fixture.localStore).synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceA,
            removedDeviceIDs: []
        )

        XCTAssertNil(result.winner)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.didWriteReplica)
    }

    func testStableWinnerDoesNotRewriteCurrentDeviceReplica() throws {
        let fixture = makeFixture()
        let local = try fixture.localStore.update(
            value: "stable-placeholder",
            for: .bailianAPIKey,
            deviceID: deviceA
        )
        let engine = CredentialSyncEngine(localStore: fixture.localStore)
        let replicaURL = fixture.syncRoot.appendingPathComponent(
            "credentials/replicas/\(deviceA).v1.json"
        )

        let first = try engine.synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceA,
            removedDeviceIDs: []
        )
        let sentinelDate = Date(timeIntervalSince1970: 123)
        try FileManager.default.setAttributes(
            [.modificationDate: sentinelDate],
            ofItemAtPath: replicaURL.path
        )
        let second = try engine.synchronize(
            rootURL: fixture.syncRoot,
            currentDeviceID: deviceA,
            removedDeviceIDs: []
        )

        XCTAssertTrue(first.didWriteReplica)
        XCTAssertFalse(second.didWriteReplica)
        XCTAssertEqual(second.winner, local)
        let attributes = try FileManager.default.attributesOfItem(atPath: replicaURL.path)
        let modificationDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
        XCTAssertEqual(
            modificationDate.timeIntervalSince1970,
            sentinelDate.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    private func makeFixture() -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = MacToolsStorePaths(
            supportDirectory: root.appendingPathComponent("support", isDirectory: true)
        )
        return Fixture(
            paths: paths,
            localStore: EncryptedCredentialStore(
                envelopeURL: paths.bailianCredentialURL,
                migrationMarkerURL: paths.credentialMigrationMarkerURL
            ),
            syncRoot: root.appendingPathComponent("MacTools Sync", isDirectory: true)
        )
    }
}

private struct Fixture {
    var paths: MacToolsStorePaths
    var localStore: EncryptedCredentialStore
    var syncRoot: URL
}
