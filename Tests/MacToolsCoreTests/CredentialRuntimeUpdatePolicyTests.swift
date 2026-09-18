import XCTest
@testable import MacToolsCore

final class CredentialRuntimeUpdatePolicyTests: XCTestCase {
    func testCloudEchoSkipsDecryptionButChangesAndRecoveryStillReload() {
        XCTAssertFalse(CredentialRuntimeUpdatePolicy.shouldReloadLocal(
            loadFinished: true, isUnavailable: false, settingsValue: "placeholder", cloudValue: "placeholder"
        ))
        XCTAssertFalse(CredentialRuntimeUpdatePolicy.shouldReloadLocal(
            loadFinished: true, isUnavailable: false, settingsValue: "", cloudValue: nil
        ))
        XCTAssertTrue(CredentialRuntimeUpdatePolicy.shouldReloadLocal(
            loadFinished: false, isUnavailable: false, settingsValue: "placeholder", cloudValue: "placeholder"
        ))
        XCTAssertTrue(CredentialRuntimeUpdatePolicy.shouldReloadLocal(
            loadFinished: true, isUnavailable: true, settingsValue: "placeholder", cloudValue: "placeholder"
        ))
        XCTAssertTrue(CredentialRuntimeUpdatePolicy.shouldReloadLocal(
            loadFinished: true, isUnavailable: false, settingsValue: "placeholder", cloudValue: nil
        ))
        XCTAssertTrue(CredentialRuntimeUpdatePolicy.shouldReloadLocal(
            loadFinished: true, isUnavailable: false, settingsValue: "old-placeholder", cloudValue: "new-placeholder"
        ))
    }

    func testStableAvailableCredentialDoesNotPublishOrRefreshServices() {
        let decision = CredentialRuntimeUpdatePolicy.decision(
            settingsValue: "stable-placeholder",
            publishedValue: "stable-placeholder",
            isUnavailable: false,
            loadedValue: "stable-placeholder"
        )

        XCTAssertFalse(decision.shouldUpdatePublishedValue)
        XCTAssertFalse(decision.shouldClearUnavailableState)
        XCTAssertFalse(decision.shouldRefreshDependentServices)
    }

    func testStableUnavailableCredentialOnlyClearsUnavailableState() {
        let decision = CredentialRuntimeUpdatePolicy.decision(
            settingsValue: "stable-placeholder",
            publishedValue: "stable-placeholder",
            isUnavailable: true,
            loadedValue: "stable-placeholder"
        )

        XCTAssertFalse(decision.shouldUpdatePublishedValue)
        XCTAssertTrue(decision.shouldClearUnavailableState)
        XCTAssertFalse(decision.shouldRefreshDependentServices)
    }

    func testChangedCredentialPublishesAndRefreshesServices() {
        let decision = CredentialRuntimeUpdatePolicy.decision(
            settingsValue: "old-placeholder",
            publishedValue: "old-placeholder",
            isUnavailable: false,
            loadedValue: "new-placeholder"
        )

        XCTAssertTrue(decision.shouldUpdatePublishedValue)
        XCTAssertFalse(decision.shouldClearUnavailableState)
        XCTAssertTrue(decision.shouldRefreshDependentServices)
    }
}
