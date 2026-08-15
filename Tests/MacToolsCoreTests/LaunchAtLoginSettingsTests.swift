import Foundation
import XCTest
@testable import MacToolsCore

final class LaunchAtLoginSettingsTests: XCTestCase {
    func testPresentationStateReflectsSystemRegistration() {
        XCTAssertFalse(LaunchAtLoginSettingsState.disabled.isEnabled)
        XCTAssertTrue(LaunchAtLoginSettingsState.enabled.isEnabled)
        XCTAssertTrue(LaunchAtLoginSettingsState.requiresApproval.isEnabled)
        XCTAssertFalse(
            LaunchAtLoginSettingsState.failed(isEnabled: false, message: "开启失败").isEnabled
        )
        XCTAssertTrue(
            LaunchAtLoginSettingsState.failed(isEnabled: true, message: "关闭失败").isEnabled
        )
        XCTAssertFalse(LaunchAtLoginSettingsState.unavailable.isAvailable)
    }

    func testEditorKeepsSystemActionsInjected() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/UI/Settings/LaunchAtLoginSettingsEditor.swift"
        )

        XCTAssertTrue(source.contains("Text(\"登录时自动启动\")"))
        XCTAssertTrue(source.contains("isOn: Binding(get: { state.isEnabled }, set: setEnabled)"))
        XCTAssertTrue(source.contains(".disabled(!state.isAvailable)"))
        XCTAssertTrue(source.contains("if state.requiresSystemApproval"))
        XCTAssertTrue(source.contains("action: openSystemSettings"))
        XCTAssertFalse(source.contains("import ServiceManagement"))
    }

    func testPlatformServiceUsesMainAppAndMapsEveryKnownStatus() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/LoginItems/SystemLaunchAtLoginService.swift"
        )

        XCTAssertTrue(source.contains("import ServiceManagement"))
        XCTAssertTrue(source.contains("SMAppService = .mainApp"))
        XCTAssertTrue(source.contains("try service.register()"))
        XCTAssertTrue(source.contains("try service.unregister()"))
        XCTAssertTrue(source.contains("SMAppService.openSystemSettingsLoginItems"))
        XCTAssertTrue(source.contains("case .requiresApproval:"))
        XCTAssertTrue(source.contains("case .notFound:"))
    }

    func testRuntimeRefreshesStateAfterReturningFromSystemSettings() throws {
        let source = try sourceFile("Sources/MacTools/Application/RuntimeViews.swift")

        XCTAssertTrue(source.contains("launchAtLoginState: launchAtLoginService.state"))
        XCTAssertTrue(source.contains("setLaunchAtLoginEnabled: launchAtLoginService.setEnabled"))
        XCTAssertTrue(source.contains("openLoginItemsSettings: launchAtLoginService.openSystemSettings"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "launchAtLoginService.refresh()").count - 1,
            2
        )
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
