import Darwin
import Foundation
import XCTest
@testable import MacToolsCore

final class EncryptedCredentialStoreTests: XCTestCase {
    private let codec = CredentialEnvelopeCodec()

    func testStorePathsKeepCredentialFilesInsideUnifiedStore() {
        let support = URL(fileURLWithPath: "/temporary-support", isDirectory: true)
        let paths = MacToolsStorePaths(supportDirectory: support)

        XCTAssertEqual(
            paths.credentialsDirectory,
            support.appendingPathComponent("Store/Credentials", isDirectory: true)
        )
        XCTAssertEqual(
            paths.bailianCredentialURL,
            support.appendingPathComponent("Store/Credentials/bailian-api-key.v1.json")
        )
        XCTAssertEqual(
            paths.credentialMigrationMarkerURL,
            support.appendingPathComponent("Store/Credentials/migration-v1.complete")
        )
    }

    func testMissingFilesReturnNoEnvelopeAndIncompleteMigration() throws {
        let fixture = makeFixture()

        XCTAssertNil(try fixture.store.readEnvelope(for: .bailianAPIKey))
        XCTAssertFalse(try fixture.store.isMigrationComplete())
    }

    func testWriteReadsBackEnvelopeAndAppliesPrivatePermissions() throws {
        let fixture = makeFixture()
        let envelope = try makeEnvelope(value: "placeholder-value", counter: 1)

        try fixture.store.write(envelope, for: .bailianAPIKey)

        XCTAssertEqual(
            try fixture.store.readEnvelope(for: .bailianAPIKey),
            envelope
        )
        XCTAssertEqual(posixMode(at: fixture.paths.credentialsDirectory), 0o700)
        XCTAssertEqual(posixMode(at: fixture.paths.bailianCredentialURL), 0o600)
    }

    func testDeletedEnvelopeRemainsAsTombstone() throws {
        let fixture = makeFixture()
        let envelope = try makeEnvelope(value: nil, counter: 2)

        try fixture.store.write(envelope, for: .bailianAPIKey)

        let record = try fixture.store.readRecord(for: .bailianAPIKey)
        XCTAssertEqual(record?.state, .deleted)
        XCTAssertNil(record?.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.bailianCredentialURL.path))
    }

    func testInvalidReplacementLeavesPreviousEnvelopeUntouched() throws {
        let fixture = makeFixture()
        let original = try makeEnvelope(value: "old-placeholder", counter: 1)
        try fixture.store.write(original, for: .bailianAPIKey)
        var invalid = try makeEnvelope(value: "new-placeholder", counter: 2)
        invalid.clock.counter += 1

        XCTAssertThrowsError(try fixture.store.write(invalid, for: .bailianAPIKey))
        XCTAssertEqual(
            try fixture.store.readEnvelope(for: .bailianAPIKey),
            original
        )
    }

    func testAtomicReplacementFailureLeavesPreviousEnvelopeUntouched() throws {
        let fixture = makeFixture()
        let original = try makeEnvelope(value: "old-placeholder", counter: 1)
        let replacement = try makeEnvelope(value: "new-placeholder", counter: 2)
        try fixture.store.write(original, for: .bailianAPIKey)
        let path = fixture.paths.bailianCredentialURL.path
        XCTAssertEqual(chflags(path, UInt32(UF_IMMUTABLE)), 0)
        defer {
            _ = chflags(path, 0)
        }

        XCTAssertThrowsError(
            try fixture.store.write(replacement, for: .bailianAPIKey)
        )
        XCTAssertEqual(chflags(path, 0), 0)
        XCTAssertEqual(
            try fixture.store.readEnvelope(for: .bailianAPIKey),
            original
        )
    }

    func testCorruptedEnvelopeIsRejected() throws {
        let fixture = makeFixture()
        try FileManager.default.createDirectory(
            at: fixture.paths.credentialsDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.paths.bailianCredentialURL)

        XCTAssertThrowsError(try fixture.store.readEnvelope(for: .bailianAPIKey))
    }

    func testMigrationMarkerIsVersionedAndPrivate() throws {
        let fixture = makeFixture()

        try fixture.store.markMigrationComplete()

        XCTAssertTrue(try fixture.store.isMigrationComplete())
        XCTAssertEqual(
            try String(contentsOf: fixture.paths.credentialMigrationMarkerURL, encoding: .utf8),
            "1\n"
        )
        XCTAssertEqual(posixMode(at: fixture.paths.credentialMigrationMarkerURL), 0o600)
    }

    func testUnsupportedMigrationMarkerIsRejectedWithoutLookingComplete() throws {
        let fixture = makeFixture()
        try FileManager.default.createDirectory(
            at: fixture.paths.credentialsDirectory,
            withIntermediateDirectories: true
        )
        try Data("2\n".utf8).write(to: fixture.paths.credentialMigrationMarkerURL)

        XCTAssertThrowsError(try fixture.store.isMigrationComplete()) {
            XCTAssertEqual(
                $0 as? EncryptedCredentialStoreError,
                .unsupportedMigrationMarker("2")
            )
        }
    }

    private func makeFixture() -> (
        store: EncryptedCredentialStore,
        paths: MacToolsStorePaths
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = MacToolsStorePaths(supportDirectory: root)
        return (
            EncryptedCredentialStore(
                envelopeURL: paths.bailianCredentialURL,
                migrationMarkerURL: paths.credentialMigrationMarkerURL
            ),
            paths
        )
    }

    private func makeEnvelope(value: String?, counter: Int64) throws -> CredentialEnvelope {
        try codec.seal(
            value: value,
            for: .bailianAPIKey,
            clock: ClipboardFieldClock(counter: counter, deviceID: "device-a"),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(counter))
        )
    }

    private func posixMode(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}
