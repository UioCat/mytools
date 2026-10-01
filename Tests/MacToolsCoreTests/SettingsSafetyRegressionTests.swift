import Foundation
import GRDB
import XCTest
@testable import MacToolsCore

final class SettingsSafetyRegressionTests: XCTestCase {
    func testRemoteTranslationCredentialNeverEntersPreferencesOrExportedClocks() throws {
        let database = try makeDatabase()
        let repository = PreferenceRepository(database: database)
        try repository.save(.defaults, enqueuesSyncChange: false)
        let remote = PreferenceDomainDocument(
            domain: "preferences.translation",
            value: Data("{\"translation\":{\"apiKey\":\"remote-placeholder\",\"model\":\"peer-model\",\"futureOption\":true}}".utf8),
            clocks: [
                "translation.apiKey": .init(counter: 9, deviceID: "peer"),
                "translation.apiKey.nested": .init(counter: 9, deviceID: "peer"),
                "translation.model": .init(counter: 9, deviceID: "peer"),
                "translation.futureOption": .init(counter: 9, deviceID: "peer")
            ],
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let loaded = try repository.applyRemoteDomain(remote)
        let persisted = try XCTUnwrap(repository.rawData())
        let exported = try XCTUnwrap(repository.domainDocument("preferences.translation"))

        XCTAssertEqual(loaded.translation.apiKey, "")
        XCTAssertEqual(loaded.translation.model, "peer-model")
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("apiKey"))
        XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains("remote-placeholder"))
        XCTAssertFalse(String(decoding: exported.value, as: UTF8.self).contains("apiKey"))
        XCTAssertNil(exported.clocks["translation.apiKey"])
        XCTAssertNil(exported.clocks["translation.apiKey.nested"])
        XCTAssertEqual(exported.clocks["translation.model"]?.counter, 9)
        XCTAssertTrue(String(decoding: exported.value, as: UTF8.self).contains("futureOption"))
        let storedCredentialClocks = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM preference_field_clocks WHERE fieldPath = 'translation.apiKey' OR fieldPath LIKE 'translation.apiKey.%'")
        }
        XCTAssertEqual(storedCredentialClocks, 0)
    }

    func testPersistedMinimumAndMaximumCacheIntegersDecodeWithoutOverflow() throws {
        for (input, expected) in [(Int.min, 200), (Int.max, 2048)] {
            let data = Data("{\"clipboard\":{\"maxCacheMegabytes\":\(input)}}".utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            XCTAssertEqual(settings.clipboard.maxCacheMegabytes, expected)
        }
    }

    func testPreviouslyStoredCredentialIsExcludedFromExportAndCleanedOnMerge() throws {
        let database = try makeDatabase()
        let repository = PreferenceRepository(database: database)
        try repository.save(.defaults, enqueuesSyncChange: false)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(repository.rawData())) as? [String: Any])
        var translation = try XCTUnwrap(root["translation"] as? [String: Any])
        translation["apiKey"] = ["nested": "old-placeholder"]
        root["translation"] = translation
        let oldData = try JSONSerialization.data(withJSONObject: root)
        try database.writer.write { db in
            try db.execute(sql: "UPDATE preferences SET value = ? WHERE domain = ?", arguments: [oldData, PreferenceRepository.appDomain])
            try db.execute(sql: "INSERT INTO preference_field_clocks(domain, fieldPath, counter, deviceID, updatedAt) VALUES ('preferences.translation', 'translation.apiKey.nested', 9, 'peer', ?)", arguments: [Date(timeIntervalSince1970: 100)])
        }
        let exported = try XCTUnwrap(repository.domainDocument("preferences.translation"))
        XCTAssertFalse(String(decoding: exported.value, as: UTF8.self).contains("apiKey"))
        XCTAssertNil(exported.clocks["translation.apiKey.nested"])

        _ = try repository.applyRemoteDomain(.init(domain: "preferences.translation", value: Data("{\"translation\":{}}".utf8), clocks: [:], updatedAt: Date(timeIntervalSince1970: 200)))
        XCTAssertFalse(String(decoding: try XCTUnwrap(repository.rawData()), as: UTF8.self).contains("apiKey"))
        let count = try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM preference_field_clocks WHERE fieldPath LIKE 'translation.apiKey.%'") }
        XCTAssertEqual(count, 0)
    }

    func testRemoteMaximumPreferenceClockRejectsNextSaveAndRollsBackTransaction() throws {
        let database = try makeDatabase()
        let repository = PreferenceRepository(database: database)
        try repository.save(.defaults, enqueuesSyncChange: false)
        let remote = PreferenceDomainDocument(
            domain: "preferences.translation",
            value: Data("{\"translation\":{\"model\":\"peer-model\"}}".utf8),
            clocks: ["translation.model": .init(counter: Int64.max, deviceID: "peer")],
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var settings = try repository.applyRemoteDomain(remote)
        let previous = try repository.rawData()
        settings.translation.model = "local-model"
        settings.appearanceMode = .dark

        XCTAssertThrowsError(try repository.save(settings, deviceSyncEnabled: true)) { error in
            XCTAssertEqual(error as? PreferenceRepositoryError, .clockExhausted(domain: "preferences.translation", fieldPath: "translation.model"))
        }

        XCTAssertEqual(try repository.rawData(), previous)
        XCTAssertFalse(try DeviceOverrideRepository(database: database).isSyncEnabled())
        XCTAssertEqual(try repository.domainDocument("preferences.translation")?.clocks["translation.model"]?.counter, Int64.max)
        let outboxCount = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox")
        }
        XCTAssertEqual(outboxCount, 0)
    }

    func testMaximumCredentialClockRejectsUpdateWithoutChangingEnvelope() throws {
        let directory = makeTemporaryDirectory()
        let paths = MacToolsStorePaths(supportDirectory: directory)
        let store = EncryptedCredentialStore(
            envelopeURL: paths.bailianCredentialURL,
            migrationMarkerURL: paths.credentialMigrationMarkerURL
        )
        let envelope = try CredentialEnvelopeCodec().seal(
            value: "old-placeholder",
            for: .bailianAPIKey,
            clock: .init(counter: Int64.max, deviceID: "peer"),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.write(envelope, for: .bailianAPIKey)

        XCTAssertThrowsError(try store.update(value: "new-placeholder", for: .bailianAPIKey, deviceID: "local")) { error in
            XCTAssertEqual(error as? EncryptedCredentialStoreError, .clockExhausted)
        }
        XCTAssertEqual(try store.readEnvelope(for: .bailianAPIKey), envelope)
    }

    func testMaximumMinimumCredentialCounterRejectsCreatingEnvelope() throws {
        let paths = MacToolsStorePaths(supportDirectory: makeTemporaryDirectory())
        let store = EncryptedCredentialStore(
            envelopeURL: paths.bailianCredentialURL,
            migrationMarkerURL: paths.credentialMigrationMarkerURL
        )
        XCTAssertThrowsError(try store.update(value: "placeholder", for: .bailianAPIKey, deviceID: "local", minimumCounter: Int64.max)) { error in
            XCTAssertEqual(error as? EncryptedCredentialStoreError, .clockExhausted)
        }
        XCTAssertNil(try store.readEnvelope(for: .bailianAPIKey))
    }

    private func makeDatabase() throws -> MacToolsDatabase {
        try MacToolsDatabase.at(makeTemporaryDirectory().appendingPathComponent("test.sqlite"))
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}
