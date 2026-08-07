import Foundation
import XCTest
@testable import MacToolsCore

final class SoftwareUpdateSettingsTests: XCTestCase {
    func testPresentationStateContainsOnlyUserFacingVersion() {
        let state = SoftwareUpdateSettingsState(
            version: "0.2.0",
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        XCTAssertEqual(state.version, "0.2.0")
    }

    func testGeneralSettingsContainsDedicatedSoftwareUpdateSection() {
        XCTAssertEqual(
            SettingsPane.general.sections,
            [.system, .softwareUpdate, .shortcuts]
        )
    }

    func testSoftwareUpdateEditorKeepsActionsInjected() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/UI/Settings/SoftwareUpdateSettingsEditor.swift"
        )

        XCTAssertTrue(source.contains("Button(action: checkForUpdates)"))
        XCTAssertTrue(source.contains("Text(\"MacTools \\(state.version)\")"))
        XCTAssertTrue(source.contains("Text(\"当前已安装版本\")"))
        XCTAssertFalse(source.contains("state.buildNumber"))
        XCTAssertFalse(source.contains("构建"))
        XCTAssertTrue(source.contains("SettingsSectionDivider()"))
        XCTAssertTrue(source.contains("title: \"自动检查更新\""))
        XCTAssertTrue(source.contains("title: \"自动下载并安装更新\""))
        XCTAssertTrue(source.contains("Toggle(title, isOn: isOn)"))
        XCTAssertTrue(source.contains(".controlSize(.small)"))
        XCTAssertTrue(source.contains(".frame(minHeight: 50)"))
        XCTAssertTrue(source.contains(".disabled(!state.automaticallyChecksForUpdates)"))
        XCTAssertFalse(source.contains("import Sparkle"))
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
