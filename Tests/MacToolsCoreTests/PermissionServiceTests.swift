import XCTest
@testable import MacToolsCore

final class PermissionServiceTests: XCTestCase {
    func testSummaryDisablesSuperRightClickWithoutAccessibilityPermission() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: false,
                hasInputMonitoring: true,
                hasPostEvent: true
            )
        )

        let summary = service.summary()

        XCTAssertFalse(summary.hasAccessibility)
        XCTAssertTrue(summary.hasInputMonitoring)
        XCTAssertTrue(summary.hasPostEvent)
        XCTAssertFalse(summary.canUseSuperRightClick)
        XCTAssertTrue(summary.canPasteAutomatically)
    }

    func testPasteAutomationUsesPostEventPermissionInsteadOfAccessibilityPermission() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: false,
                hasInputMonitoring: false,
                hasPostEvent: true
            )
        )

        let summary = service.summary()

        XCTAssertTrue(summary.canPasteAutomatically)
    }

    func testMissingPermissionsAreReportedInStableOrder() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: false,
                hasInputMonitoring: false,
                hasPostEvent: false
            )
        )

        let summary = service.summary()

        XCTAssertEqual(summary.missingPermissions, [.accessibility, .inputMonitoring, .postEvent])
    }

    func testAllGrantedSummaryHasNoMissingPermissions() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: true,
                hasInputMonitoring: true,
                hasPostEvent: true
            )
        )

        let summary = service.summary()

        XCTAssertEqual(
            summary,
            PermissionSummary(hasAccessibility: true, hasInputMonitoring: true, hasPostEvent: true)
        )
        XCTAssertTrue(summary.canUseSuperRightClick)
        XCTAssertTrue(summary.canPasteAutomatically)
        XCTAssertEqual(summary.missingPermissions, [])
    }

    func testPermissionSpecificSystemSettingsURLs() throws {
        XCTAssertEqual(
            PermissionService.systemSettingsURL(for: .accessibility),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
        XCTAssertEqual(
            PermissionService.systemSettingsURL(for: .inputMonitoring),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        )
        XCTAssertEqual(
            PermissionService.systemSettingsURL(for: .postEvent),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        )
    }
}

private struct FakePermissionChecker: PermissionChecking {
    var hasAccessibility: Bool
    var hasInputMonitoring: Bool
    var hasPostEvent: Bool

    func hasAccessibilityPermission() -> Bool {
        hasAccessibility
    }

    func hasInputMonitoringPermission() -> Bool {
        hasInputMonitoring
    }

    func hasPostEventPermission() -> Bool {
        hasPostEvent
    }
}
