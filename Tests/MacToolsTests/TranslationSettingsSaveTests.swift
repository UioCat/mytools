import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

@MainActor
final class TranslationSettingsSaveTests: XCTestCase {
    func testCredentialSaveMergesTranslationIntoSettingsChangedDuringAwait() async throws {
        let runtime = try makeRuntime()
        let save = Task { try await runtime.save(.init(apiKey: " new-placeholder ", model: "new-model"), edited: true) }
        await runtime.writer.waitForRequest("new-placeholder")

        runtime.settings.appearanceMode = .dark
        runtime.settings.clipboard = ClipboardSettings(isRecordingEnabled: false, maxHistoryCount: 500, maxCacheMegabytes: 2048)
        runtime.settings.mainPanelShortcut = .init(key: "8", modifiers: ["Option"])
        try runtime.preferences.save(runtime.settings)
        runtime.writer.succeed("new-placeholder")
        let result = try await save.value

        XCTAssertEqual(result.appearanceMode, .dark)
        XCTAssertFalse(result.clipboard.isRecordingEnabled)
        XCTAssertEqual(result.clipboard.maxCacheMegabytes, 2048)
        XCTAssertEqual(result.mainPanelShortcut.key, "8")
        XCTAssertEqual(result.translation.model, "new-model")
        XCTAssertEqual(result.translation.apiKey, "new-placeholder")
        XCTAssertEqual(try runtime.preferences.load()?.appearanceMode, .dark)
        XCTAssertEqual(try runtime.preferences.load()?.clipboard.isRecordingEnabled, false)
        XCTAssertEqual(runtime.publishedCredential, "new-placeholder")
    }

    func testNewerTranslationSaveSupersedesOldDraftAndSerializesCredentialWrites() async throws {
        let runtime = try makeRuntime()
        let first = Task { try await runtime.save(.init(apiKey: "first-placeholder", model: "first-model"), edited: true) }
        await runtime.writer.waitForRequest("first-placeholder")
        let second = Task { try await runtime.save(.init(apiKey: "second-placeholder", model: "second-model"), edited: true) }
        await runtime.waitForSaveCount(2)

        XCTAssertEqual(runtime.writer.requestCount, 1, "Credential writes must preserve user save order")
        runtime.writer.succeed("first-placeholder")
        await runtime.writer.waitForRequest("second-placeholder")
        runtime.writer.succeed("second-placeholder")
        _ = try await second.value
        do {
            _ = try await first.value
            XCTFail("The superseded draft should not report a completed save")
        } catch is CancellationError {
            // Superseded by the newer draft.
        }

        XCTAssertEqual(runtime.settings.translation.model, "second-model")
        XCTAssertEqual(runtime.settings.translation.apiKey, "second-placeholder")
        XCTAssertEqual(runtime.publishedCredential, "second-placeholder")
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.value, "second-placeholder")
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.clock.counter, 3)
        XCTAssertEqual(try runtime.preferences.load()?.translation.model, "second-model")
        XCTAssertEqual(runtime.publishCount, 1)
    }

    func testUneditedNewerDraftRetainsCredentialFromPendingSave() async throws {
        let runtime = try makeRuntime()
        let first = Task { try await runtime.save(.init(apiKey: "new-placeholder", model: "first-model"), edited: true) }
        await runtime.writer.waitForRequest("new-placeholder")
        let second = Task { try await runtime.save(.init(apiKey: "", model: "second-model"), edited: false) }
        await runtime.waitForSaveCount(2)
        runtime.writer.succeed("new-placeholder")
        _ = try await second.value
        _ = try? await first.value

        XCTAssertEqual(runtime.settings.translation.model, "second-model")
        XCTAssertEqual(runtime.settings.translation.apiKey, "new-placeholder")
        XCTAssertEqual(runtime.publishedCredential, "new-placeholder")
        XCTAssertEqual(runtime.writer.requestCount, 1)
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.value, "new-placeholder")
    }

    func testOldCredentialSaveFailureDoesNotMarkNewerSaveUnavailable() async throws {
        let runtime = try makeRuntime()
        let first = Task { try await runtime.save(.init(apiKey: "first-placeholder", model: "first-model"), edited: true) }
        await runtime.writer.waitForRequest("first-placeholder")
        let second = Task { try await runtime.save(.init(apiKey: "second-placeholder", model: "second-model"), edited: true) }
        await runtime.waitForSaveCount(2)
        runtime.writer.fail("first-placeholder")
        await runtime.writer.waitForRequest("second-placeholder")
        runtime.writer.succeed("second-placeholder")
        _ = try await second.value
        _ = try? await first.value

        XCTAssertEqual(runtime.failureCount, 0)
        XCTAssertFalse(runtime.isUnavailable)
        XCTAssertEqual(runtime.settings.translation.apiKey, "second-placeholder")
    }

    func testSupersededCredentialCommitSurvivesNewerWriteFailureAndUneditedSave() async throws {
        let runtime = try makeRuntime()
        let first = Task { try await runtime.save(.init(apiKey: "first-placeholder", model: "first-model"), edited: true) }
        await runtime.writer.waitForRequest("first-placeholder")
        let second = Task { try await runtime.save(.init(apiKey: "second-placeholder", model: "second-model"), edited: true) }
        await runtime.waitForSaveCount(2)
        runtime.writer.succeed("first-placeholder")
        await runtime.writer.waitForRequest("second-placeholder")
        XCTAssertEqual(runtime.settings.translation.apiKey, "first-placeholder")
        XCTAssertEqual(runtime.publishedCredential, "first-placeholder")
        XCTAssertFalse(runtime.isUnavailable)
        XCTAssertEqual(runtime.settings.translation.model, TranslationSettings.defaultModel)
        runtime.writer.fail("second-placeholder")
        _ = try? await first.value
        do { _ = try await second.value; XCTFail("Expected latest credential failure") }
        catch TestFailure.writeFailed {}
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.value, "first-placeholder")
        XCTAssertEqual(runtime.settings.translation.apiKey, "first-placeholder")
        XCTAssertEqual(runtime.publishedCredential, "first-placeholder")
        let result = try await runtime.save(.init(apiKey: "old-placeholder", model: "third-model"), edited: false)
        XCTAssertFalse(runtime.isUnavailable)
        XCTAssertEqual(result.translation.apiKey, "first-placeholder")
        XCTAssertEqual(result.translation.model, "third-model")
        XCTAssertEqual(runtime.publishCount, 1)
    }

    func testCredentialFailureWithDamagedEnvelopeReportsUnavailable() async throws {
        let runtime = try makeRuntime()
        let save = Task { try await runtime.save(.init(apiKey: "new-placeholder"), edited: true) }
        await runtime.writer.waitForRequest("new-placeholder")
        try Data("synthetic-invalid-envelope".utf8).write(to: runtime.credentialEnvelopeURL, options: .atomic)
        runtime.writer.fail("new-placeholder")
        _ = try? await save.value
        XCTAssertTrue(runtime.isUnavailable)
        XCTAssertEqual(runtime.failureCount, 1)
    }

    func testStaleFailureReadbackCannotReplaceNewerSuccessfulCredential() async throws {
        let runtime = try makeRuntime()
        let reload = SuspendedCredentialWriter()
        runtime.reloadOverride = { try await reload.save("reload-placeholder"); return "stale-placeholder" }
        let first = Task { try await runtime.save(.init(apiKey: "first-placeholder"), edited: true) }
        await runtime.writer.waitForRequest("first-placeholder")
        runtime.writer.fail("first-placeholder")
        await reload.waitForRequest("reload-placeholder")
        let second = Task { try await runtime.save(.init(apiKey: "second-placeholder"), edited: true) }
        await runtime.writer.waitForRequest("second-placeholder")
        runtime.writer.succeed("second-placeholder")
        _ = try await second.value
        reload.succeed("reload-placeholder")
        _ = try? await first.value
        XCTAssertEqual(runtime.publishedCredential, "second-placeholder")
        XCTAssertEqual(runtime.settings.translation.apiKey, "second-placeholder")
        XCTAssertFalse(runtime.isUnavailable)
    }

    func testCurrentCredentialWriteFailurePreservesPreferencesAndAvailablePreviousCredential() async throws {
        let runtime = try makeRuntime()
        let original = try runtime.preferences.rawData()
        let save = Task { try await runtime.save(.init(apiKey: "new-placeholder", model: "new-model"), edited: true) }
        await runtime.writer.waitForRequest("new-placeholder")
        runtime.writer.fail("new-placeholder")
        do {
            _ = try await save.value
            XCTFail("Expected credential write failure")
        } catch TestFailure.writeFailed {
            // Expected.
        }
        XCTAssertEqual(try runtime.preferences.rawData(), original)
        XCTAssertEqual(runtime.settings.translation.apiKey, "initial-placeholder")
        XCTAssertFalse(runtime.isUnavailable)
        XCTAssertEqual(runtime.failureCount, 0)
        XCTAssertEqual(runtime.publishCount, 0)
    }

    func testUneditedSaveResolvesCredentialFromCurrentRuntime() async throws {
        let runtime = try makeRuntime()
        runtime.settings.translation.apiKey = "cloud-placeholder"
        let result = try await runtime.save(.init(apiKey: "old-placeholder", model: "new-model"), edited: false)
        XCTAssertEqual(result.translation.apiKey, "cloud-placeholder")
        XCTAssertEqual(result.translation.model, "new-model")
        XCTAssertEqual(runtime.writer.requestCount, 0)
    }

    func testPreferenceFailurePreservesCommittedCredentialAndPreviousSettings() async throws {
        let runtime = try makeRuntime()
        let originalData = try runtime.preferences.rawData()
        runtime.rejectPreferences = true
        let save = Task { try await runtime.save(.init(apiKey: "new-placeholder", model: "new-model"), edited: true) }
        await runtime.writer.waitForRequest("new-placeholder")
        runtime.writer.succeed("new-placeholder")
        do {
            _ = try await save.value
            XCTFail("Expected preference persistence failure")
        } catch TestFailure.preferencesFailed {
            // Credential and preference stores are independent transactions.
        }
        XCTAssertEqual(try runtime.preferences.rawData(), originalData)
        XCTAssertEqual(runtime.settings.translation.model, TranslationSettings.defaultModel)
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.value, "new-placeholder")
        XCTAssertEqual(runtime.publishCount, 0)
        XCTAssertEqual(runtime.publishedCredential, "new-placeholder", "A committed credential must be delivered even when preference persistence fails")
        XCTAssertEqual(runtime.settings.translation.apiKey, "new-placeholder")
        XCTAssertFalse(runtime.isCredentialSaving)
    }

    func testSupersededCloudLoadFailureCannotSetUnavailable() async {
        let loader = SuspendedCredentialWriter()
        var generation = 1
        var isUnavailable = false
        let load = Task {
            await CredentialLoadRequest.perform(
                isCurrent: { generation == 1 },
                load: { try await loader.save("load-placeholder"); return "loaded-placeholder" },
                onLoaded: { _ in isUnavailable = false },
                onFailure: { _ in isUnavailable = true }
            )
        }
        await loader.waitForRequest("load-placeholder")
        generation = 2
        loader.fail("load-placeholder")
        await load.value
        XCTAssertFalse(isUnavailable)
    }

    func testCurrentCloudLoadFailureReportsUnavailable() async {
        let loader = SuspendedCredentialWriter()
        var isUnavailable = false
        let load = Task {
            await CredentialLoadRequest.perform(
                isCurrent: { true },
                load: { try await loader.save("load-placeholder"); return "loaded-placeholder" },
                onLoaded: { _ in isUnavailable = false },
                onFailure: { _ in isUnavailable = true }
            )
        }
        await loader.waitForRequest("load-placeholder")
        loader.fail("load-placeholder")
        await load.value
        XCTAssertTrue(isUnavailable)
    }

    func testSupersededCloudLoadSuccessCannotReplaceCurrentValue() async {
        let loader = SuspendedCredentialWriter()
        var generation = 1
        var value = "current-placeholder"
        let load = Task {
            await CredentialLoadRequest.perform(
                isCurrent: { generation == 1 },
                load: { try await loader.save("load-placeholder"); return "old-placeholder" },
                onLoaded: { value = $0 },
                onFailure: { _ in XCTFail("Unexpected failure") }
            )
        }
        await loader.waitForRequest("load-placeholder")
        generation = 2
        loader.succeed("load-placeholder")
        await load.value
        XCTAssertEqual(value, "current-placeholder")
    }

    func testEditedEmptyCredentialPersistsDeletionAndNormalizesProvider() async throws {
        let runtime = try makeRuntime()
        let save = Task { try await runtime.save(.init(providerID: "legacy-provider", apiKey: "", model: "new-model"), edited: true) }
        await runtime.writer.waitForRequest("")
        runtime.writer.succeed("")
        let result = try await save.value
        XCTAssertEqual(result.translation.providerID, "bailian")
        XCTAssertEqual(result.translation.apiKey, "")
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.state, .deleted)
        XCTAssertEqual(try runtime.credentialStore.readRecord(for: .bailianAPIKey)?.clock.counter, 2)
        XCTAssertFalse(runtime.isUnavailable)
    }

    private func makeRuntime() throws -> SettingsRuntime {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let paths = MacToolsStorePaths(supportDirectory: root)
        let store = EncryptedCredentialStore(envelopeURL: paths.bailianCredentialURL, migrationMarkerURL: paths.credentialMigrationMarkerURL)
        return try SettingsRuntime(database: MacToolsDatabase.at(root.appendingPathComponent("test.sqlite")), credentialStore: store,
            credentialEnvelopeURL: paths.bailianCredentialURL)
    }
}

@MainActor
private final class SettingsRuntime {
    var settings = AppSettings.defaults
    let preferences: PreferenceRepository
    let credentialStore: EncryptedCredentialStore
    let credentialEnvelopeURL: URL
    let writer: SuspendedCredentialWriter
    let credentialAccess: CredentialAccessCoordinator
    let coordinator = TranslationSettingsSaveCoordinator()
    var publishedCredential = "initial-placeholder"
    var isUnavailable = false
    var isCredentialSaving = false
    var failureCount = 0
    var publishCount = 0
    var rejectPreferences = false
    var reloadOverride: (() async throws -> String?)?
    private var saveCount = 0
    private var saveWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(database: MacToolsDatabase, credentialStore: EncryptedCredentialStore, credentialEnvelopeURL: URL) throws {
        preferences = PreferenceRepository(database: database)
        self.credentialStore = credentialStore
        self.credentialEnvelopeURL = credentialEnvelopeURL
        credentialAccess = CredentialAccessCoordinator(store: credentialStore, legacyReader: NoLegacyCredentials(), deviceID: "local")
        writer = SuspendedCredentialWriter(access: credentialAccess)
        settings.translation.apiKey = "initial-placeholder"
        _ = try credentialStore.update(value: "initial-placeholder", for: .bailianAPIKey, deviceID: "local")
        try preferences.save(settings)
    }

    func save(_ draft: TranslationSettings, edited: Bool) async throws -> AppSettings {
        saveCount += 1
        for (_, waiter) in saveWaiters.filter({ $0.0 <= saveCount }) { waiter.resume() }
        saveWaiters.removeAll { $0.0 <= saveCount }
        return try await coordinator.save(draft, apiKeyWasEdited: edited, dependencies: .init(
            currentSettings: { self.settings },
            saveCredential: { try await self.writer.save($0) },
            persistSettings: {
                if self.rejectPreferences { throw TestFailure.preferencesFailed }
                try self.preferences.save($0)
            },
            publishSettings: { self.settings = $0; self.publishCount += 1 },
            credentialSaveBegan: { self.isCredentialSaving = true },
            credentialSaveSucceeded: {
                self.publishedCredential = $0
                self.settings.translation.apiKey = $0
                self.isUnavailable = false
                self.isCredentialSaving = false
            },
            credentialSaveFailed: { self.isUnavailable = true; self.failureCount += 1; self.isCredentialSaving = false },
            reloadCredentialAfterFailure: {
                if let reload = self.reloadOverride { return try await reload() }
                return try await self.credentialAccess.loadLocal(.bailianAPIKey, fallback: "")?.value
            }
        ))
    }

    func waitForSaveCount(_ count: Int) async {
        guard saveCount < count else { return }
        await withCheckedContinuation { saveWaiters.append((count, $0)) }
    }
}

@MainActor
private final class SuspendedCredentialWriter {
    private let access: CredentialAccessCoordinator?
    private var pending: [String: CheckedContinuation<Void, Error>] = [:]
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var requestCount = 0

    init(access: CredentialAccessCoordinator? = nil) { self.access = access }

    func save(_ key: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requestCount += 1
            pending[key] = continuation
            for waiter in waiting.removeValue(forKey: key) ?? [] { waiter.resume() }
        }
        if let access { _ = try await access.save(key, for: .bailianAPIKey) }
    }

    func waitForRequest(_ key: String) async {
        guard pending[key] == nil else { return }
        await withCheckedContinuation { waiting[key, default: []].append($0) }
    }

    func succeed(_ key: String) { pending.removeValue(forKey: key)?.resume() }
    func fail(_ key: String) { pending.removeValue(forKey: key)?.resume(throwing: TestFailure.writeFailed) }
}

private enum TestFailure: Error { case writeFailed, preferencesFailed }

private struct NoLegacyCredentials: LegacyCredentialReading {
    func read(_ key: CredentialKey) throws -> String? { nil }
}
