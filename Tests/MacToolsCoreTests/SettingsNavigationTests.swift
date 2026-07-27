import Foundation
import XCTest
@testable import MacToolsCore

final class SettingsNavigationTests: XCTestCase {
    func testPanesUseStableToolbarOrder() {
        XCTAssertEqual(
            SettingsPane.allCases,
            [.general, .clipboard, .translation, .automation, .sync]
        )
        XCTAssertEqual(
            SettingsPane.allCases.map(\.title),
            ["通用", "剪贴板", "翻译", "自动化", "数据同步"]
        )
    }

    func testEachPaneOwnsOnlyItsRelatedSections() {
        XCTAssertEqual(SettingsPane.general.sections, [.system, .shortcuts])
        XCTAssertEqual(SettingsPane.clipboard.sections, [.clipboard])
        XCTAssertEqual(SettingsPane.translation.sections, [.translation])
        XCTAssertEqual(
            SettingsPane.automation.sections,
            [.superRightClick, .windowLayout, .permissions]
        )
        XCTAssertEqual(SettingsPane.sync.sections, [.sync])
    }

    func testSettingsSectionsUseQuietContentSurfaceInsteadOfLiquidGlass() throws {
        let source = try sourceFile("Sources/MacToolsCore/UI/SettingsComponents.swift")

        XCTAssertTrue(source.contains(".settingsContentSurface(cornerRadius: 20)"))
        XCTAssertFalse(source.contains(".liquidGlassModule(cornerRadius: 22)"))
    }

    func testRuntimeRetainsSelectionForCurrentAppSessionAndDefaultsToGeneral() throws {
        let source = try sourceFile("Sources/MacTools/App/RuntimeViews.swift")

        XCTAssertTrue(
            source.contains("@State private var selectedSettingsPane: SettingsPane = .general")
        )
        XCTAssertTrue(source.contains("selectedPane: $selectedSettingsPane"))
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
