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

    func testSummaryDisablesSuperRightClickWithoutInputMonitoringPermission() {
        let service = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: true,
                hasInputMonitoring: false,
                hasPostEvent: true
            )
        )

        let summary = service.summary()

        XCTAssertTrue(summary.hasAccessibility)
        XCTAssertFalse(summary.hasInputMonitoring)
        XCTAssertTrue(summary.hasPostEvent)
        XCTAssertFalse(summary.canUseSuperRightClick)
        XCTAssertEqual(summary.firstMissingSuperRightClickPermission, .inputMonitoring)
    }

    func testSummaryAllowsSuperRightClickMonitoringWithoutPostEventPermission() {
        let summary = PermissionSummary(
            hasAccessibility: true,
            hasInputMonitoring: true,
            hasPostEvent: false
        )

        XCTAssertTrue(summary.canUseSuperRightClick)
        XCTAssertNil(summary.firstMissingSuperRightClickPermission)
        XCTAssertFalse(summary.canPasteAutomatically)
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
        XCTAssertEqual(summary.missingSuperRightClickPermissions, [.accessibility, .inputMonitoring])
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

    func testRequestSuperRightClickPermissionsPromptsOnlyMissingMonitorPermissions() {
        let checker = FakePermissionChecker(
            hasAccessibility: false,
            hasInputMonitoring: false,
            hasPostEvent: false
        )
        let service = PermissionService(checker: checker)

        let summary = service.requestSuperRightClickPermissions()

        XCTAssertFalse(summary.canUseSuperRightClick)
        XCTAssertEqual(checker.accessibilityRequestCount, 1)
        XCTAssertEqual(checker.inputMonitoringRequestCount, 1)
        XCTAssertEqual(checker.postEventRequestCount, 0)
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

    func testScreenRecordingPermissionIsIncludedInSummaryAndSettingsURL() {
        let summary = PermissionService(
            checker: FakePermissionChecker(
                hasAccessibility: true,
                hasInputMonitoring: true,
                hasPostEvent: true
            )
        ).summary()

        XCTAssertFalse(summary.hasScreenRecording)
        XCTAssertEqual(
            PermissionService.systemSettingsURL(for: .screenRecording),
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        )
    }
}

private final class FakePermissionChecker: PermissionChecking {
    var hasAccessibility: Bool
    var hasInputMonitoring: Bool
    var hasPostEvent: Bool
    var hasScreenRecording: Bool
    private(set) var accessibilityRequestCount = 0
    private(set) var inputMonitoringRequestCount = 0
    private(set) var postEventRequestCount = 0

    init(
        hasAccessibility: Bool,
        hasInputMonitoring: Bool,
        hasPostEvent: Bool,
        hasScreenRecording: Bool = false
    ) {
        self.hasAccessibility = hasAccessibility
        self.hasInputMonitoring = hasInputMonitoring
        self.hasPostEvent = hasPostEvent
        self.hasScreenRecording = hasScreenRecording
    }

    func hasAccessibilityPermission() -> Bool {
        hasAccessibility
    }

    func hasInputMonitoringPermission() -> Bool {
        hasInputMonitoring
    }

    func hasPostEventPermission() -> Bool {
        hasPostEvent
    }

    func hasScreenRecordingPermission() -> Bool {
        hasScreenRecording
    }

    func requestAccessibilityPermission() -> Bool {
        accessibilityRequestCount += 1
        return hasAccessibility
    }

    func requestInputMonitoringPermission() -> Bool {
        inputMonitoringRequestCount += 1
        return hasInputMonitoring
    }

    func requestPostEventPermission() -> Bool {
        postEventRequestCount += 1
        return hasPostEvent
    }

    func requestScreenRecordingPermission() -> Bool {
        hasScreenRecording
    }
}
