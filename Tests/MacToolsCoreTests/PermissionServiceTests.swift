import XCTest
@testable import MacToolsCore

final class PermissionServiceTests: XCTestCase {
    func testSummaryDisablesSuperRightClickWithoutAccessibilityPermission() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: false,
                hasInputMonitoring: true
            )
        )

        let summary = service.summary()

        XCTAssertFalse(summary.hasAccessibility)
        XCTAssertTrue(summary.hasInputMonitoring)
        XCTAssertFalse(summary.canUseSuperRightClick)
    }

    func testMissingPermissionsAreReportedInStableOrder() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: false,
                hasInputMonitoring: false
            )
        )

        let summary = service.summary()

        XCTAssertEqual(summary.missingPermissions, [.accessibility, .inputMonitoring])
    }

    func testAllGrantedSummaryHasNoMissingPermissions() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: true,
                hasInputMonitoring: true
            )
        )

        let summary = service.summary()

        XCTAssertEqual(
            summary,
            PermissionSummary(hasAccessibility: true, hasInputMonitoring: true)
        )
        XCTAssertTrue(summary.canUseSuperRightClick)
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
    }
}

private struct FakePermissionChecker: PermissionChecking {
    var hasAccessibility: Bool
    var hasInputMonitoring: Bool

    func hasAccessibilityPermission() -> Bool {
        hasAccessibility
    }

    func hasInputMonitoringPermission() -> Bool {
        hasInputMonitoring
    }
}
