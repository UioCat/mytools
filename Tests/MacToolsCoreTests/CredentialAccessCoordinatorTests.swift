import Foundation
import XCTest
@testable import MacToolsCore

final class CredentialAccessCoordinatorTests: XCTestCase {
    func testQueuedUserSaveWinsAfterBlockedLegacyMigration() async throws {
        let fixture = makeFixture(legacyValue: "legacy-placeholder", blocksRead: true)
        let loadTask = Task {
            try await fixture.access.load(.bailianAPIKey, fallback: "")
        }

        XCTAssertEqual(
            fixture.legacyReader.firstReadStarted.wait(timeout: .now() + 1),
            .success
        )
        let saveTask = Task {
            try await fixture.access.save("new-placeholder", for: .bailianAPIKey)
        }
        fixture.legacyReader.releaseFirstRead.signal()

        let loadResult = try await loadTask.value
        _ = try await saveTask.value

        XCTAssertEqual(loadResult.value, "legacy-placeholder")
        XCTAssertEqual(
            try fixture.store.readRecord(for: .bailianAPIKey)?.value,
            "new-placeholder"
        )
        XCTAssertEqual(
            try fixture.store.readRecord(for: .bailianAPIKey)?.clock.counter,
            2
        )
    }

    func testExistingLocalRecordNeverReadsLegacyStore() async throws {
        let fixture = makeFixture(legacyValue: "legacy-placeholder")
        _ = try fixture.store.update(
            value: "local-placeholder",
            for: .bailianAPIKey,
            deviceID: fixture.deviceID
        )

        let result = try await fixture.access.load(
            .bailianAPIKey,
            fallback: "old-plaintext-placeholder"
        )

        XCTAssertEqual(result.value, "local-placeholder")
        XCTAssertTrue(result.shouldRedactLegacy)
        XCTAssertEqual(fixture.legacyReader.readCount, 0)
        XCTAssertTrue(try fixture.store.isMigrationComplete())
    }

    func testLoadLocalReturnsNilOnlyWhenLegacyBootstrapIsNeeded() async throws {
        let fixture = makeFixture(legacyValue: "legacy-placeholder")

        let local = try await fixture.access.loadLocal(
            .bailianAPIKey,
            fallback: "plaintext-placeholder"
        )

        XCTAssertNil(local)
        XCTAssertEqual(fixture.legacyReader.readCount, 0)
    }

    func testExistingDeletionNeverRevivesLegacyStore() async throws {
        let fixture = makeFixture(legacyValue: "legacy-placeholder")
        _ = try fixture.store.update(
            value: "",
            for: .bailianAPIKey,
            deviceID: fixture.deviceID
        )

        let result = try await fixture.access.load(.bailianAPIKey, fallback: "")

        XCTAssertEqual(result.value, "")
        XCTAssertEqual(fixture.legacyReader.readCount, 0)
        XCTAssertEqual(
            try fixture.store.readRecord(for: .bailianAPIKey)?.state,
            .deleted
        )
    }

    func testPlaintextFallbackMigratesBeforeLegacyReader() async throws {
        let fixture = makeFixture(legacyValue: "keychain-placeholder")

        let result = try await fixture.access.load(
            .bailianAPIKey,
            fallback: " plaintext-placeholder "
        )

        XCTAssertEqual(result.value, "plaintext-placeholder")
        XCTAssertTrue(result.shouldRedactLegacy)
        XCTAssertEqual(fixture.legacyReader.readCount, 0)
        XCTAssertTrue(try fixture.store.isMigrationComplete())
    }

    func testLegacyValueMigratesOnceAndMarksCompletion() async throws {
        let fixture = makeFixture(legacyValue: " legacy-placeholder ")

        let first = try await fixture.access.load(.bailianAPIKey, fallback: "")
        let relaunchedAccess = CredentialAccessCoordinator(
            store: fixture.store,
            legacyReader: fixture.legacyReader,
            deviceID: fixture.deviceID
        )
        let second = try await relaunchedAccess.load(.bailianAPIKey, fallback: "")

        XCTAssertEqual(first.value, "legacy-placeholder")
        XCTAssertEqual(second.value, "legacy-placeholder")
        XCTAssertEqual(fixture.legacyReader.readCount, 1)
        XCTAssertTrue(try fixture.store.isMigrationComplete())
    }

    func testMissingLegacyValueMarksCompletionAndDoesNotQueryAgain() async throws {
        let fixture = makeFixture(legacyValue: nil)

        let first = try await fixture.access.load(.bailianAPIKey, fallback: "")
        let second = try await fixture.access.load(.bailianAPIKey, fallback: "")

        XCTAssertEqual(first.value, "")
        XCTAssertEqual(second.value, "")
        XCTAssertEqual(fixture.legacyReader.readCount, 1)
        XCTAssertTrue(try fixture.store.isMigrationComplete())
    }

    func testLegacyReadFailureDoesNotMarkMigrationComplete() async throws {
        let fixture = makeFixture(legacyError: TestError.denied)

        await XCTAssertThrowsErrorAsync(
            try await fixture.access.load(.bailianAPIKey, fallback: "")
        )

        XCTAssertFalse(try fixture.store.isMigrationComplete())
        XCTAssertNil(try fixture.store.readRecord(for: .bailianAPIKey))
    }

    func testEmptySaveCreatesNewerDeletionTombstone() async throws {
        let fixture = makeFixture(legacyValue: nil)

        let active = try await fixture.access.save(
            "configured-placeholder",
            for: .bailianAPIKey
        )
        let deleted = try await fixture.access.save("", for: .bailianAPIKey)

        XCTAssertEqual(active.state, .active)
        XCTAssertEqual(deleted.state, .deleted)
        XCTAssertEqual(deleted.clock.counter, active.clock.counter + 1)
        XCTAssertNil(deleted.value)
    }

    private func makeFixture(
        legacyValue: String? = nil,
        legacyError: Error? = nil,
        blocksRead: Bool = false
    ) -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let paths = MacToolsStorePaths(supportDirectory: root)
        let store = EncryptedCredentialStore(
            envelopeURL: paths.bailianCredentialURL,
            migrationMarkerURL: paths.credentialMigrationMarkerURL
        )
        let legacyReader = FakeLegacyCredentialReader(
            value: legacyValue,
            error: legacyError,
            blocksRead: blocksRead
        )
        let deviceID = "00000000-0000-0000-0000-000000000001"
        return Fixture(
            store: store,
            legacyReader: legacyReader,
            access: CredentialAccessCoordinator(
                store: store,
                legacyReader: legacyReader,
                deviceID: deviceID,
                now: { Date(timeIntervalSince1970: 100) }
            ),
            deviceID: deviceID
        )
    }
}

private struct Fixture {
    var store: EncryptedCredentialStore
    var legacyReader: FakeLegacyCredentialReader
    var access: CredentialAccessCoordinator
    var deviceID: String
}

private enum TestError: Error {
    case denied
}

private final class FakeLegacyCredentialReader: LegacyCredentialReading, @unchecked Sendable {
    let firstReadStarted = DispatchSemaphore(value: 0)
    let releaseFirstRead = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private let value: String?
    private let error: Error?
    private var blocksRead: Bool
    private var storedReadCount = 0

    init(value: String?, error: Error?, blocksRead: Bool) {
        self.value = value
        self.error = error
        self.blocksRead = blocksRead
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedReadCount
    }

    func read(_ key: CredentialKey) throws -> String? {
        lock.lock()
        storedReadCount += 1
        let shouldBlock = blocksRead
        blocksRead = false
        lock.unlock()
        if shouldBlock {
            firstReadStarted.signal()
            _ = releaseFirstRead.wait(timeout: .now() + 2)
        }
        if let error { throw error }
        return value
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}
