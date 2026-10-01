import MacToolsCore
import XCTest
@testable import MacTools

@MainActor
final class RuntimeTranslationSettingsSaveRequestTests: XCTestCase {
    func testLateCancellationDoesNotMarkNewerSuccessfulCredentialUnavailable() async throws {
        let gate = SuspendedTranslationSettingsResult()
        var unavailable = false
        let first = Task {
            try await RuntimeTranslationSettingsSaveRequest.perform(save: { try await gate.load() },
                onSaved: { _ in XCTFail("Superseded settings must not publish") }, credentialIsUnavailable: { false },
                onCredentialUnavailableChanged: { unavailable = $0 })
        }
        await gate.waitUntilStarted()
        try await RuntimeTranslationSettingsSaveRequest.perform(save: { AppSettings.defaults }, onSaved: { _ in },
            credentialIsUnavailable: { false }, onCredentialUnavailableChanged: { unavailable = $0 })
        await gate.finish(.failure(CancellationError()))
        _ = try? await first.value
        XCTAssertFalse(unavailable)
    }

    func testPreferenceFailureKeepsAvailableCredentialStatus() async {
        var unavailable = false
        do {
            try await RuntimeTranslationSettingsSaveRequest.perform(save: { throw SettingsFailure.preferences },
                onSaved: { _ in XCTFail("Preferences failed") }, credentialIsUnavailable: { false },
                onCredentialUnavailableChanged: { unavailable = $0 })
            XCTFail("Expected preference failure")
        } catch SettingsFailure.preferences {} catch { XCTFail("Unexpected error type") }
        XCTAssertFalse(unavailable)
    }

    func testSuccessfulUneditedSaveDoesNotHideUnresolvedCredentialFailure() async throws {
        var unavailable = true
        try await RuntimeTranslationSettingsSaveRequest.perform(save: { AppSettings.defaults }, onSaved: { _ in },
            credentialIsUnavailable: { true }, onCredentialUnavailableChanged: { unavailable = $0 })
        XCTAssertTrue(unavailable)
    }
}

private enum SettingsFailure: Error { case preferences }

private actor SuspendedTranslationSettingsResult {
    private var pending: CheckedContinuation<AppSettings, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func load() async throws -> AppSettings {
        try await withCheckedThrowingContinuation { pending = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ result: Result<AppSettings, Error>) { pending?.resume(with: result); pending = nil }
}
