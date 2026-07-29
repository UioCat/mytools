import XCTest
@testable import MacToolsCore

final class CredentialRuntimeUpdatePolicyTests: XCTestCase {
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
