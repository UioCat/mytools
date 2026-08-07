import Foundation
import XCTest
@testable import MacToolsCore

final class SoftwareUpdateSettingsTests: XCTestCase {
    func testVersionDescriptionIncludesShortVersionAndBuildNumber() {
        let state = SoftwareUpdateSettingsState(
            version: "0.2.0",
            buildNumber: "42",
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: true,
            automaticallyDownloadsUpdates: false
        )

        XCTAssertEqual(state.versionDescription, "0.2.0（构建 42）")
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
        XCTAssertTrue(source.contains("Text(\"构建 \\(state.buildNumber) · 当前已安装版本\")"))
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
