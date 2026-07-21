import Foundation
import XCTest

final class SettingsColumnArrangementSourceTests: XCTestCase {
    func testPermissionsSectionFollowsSuperRightClickInPrimaryColumn() throws {
        let source = try settingsViewSource()
        let primaryColumn = try sourceFragment(
            in: source,
            from: "    private var primarySettingsColumn: some View {",
            to: "    private var secondarySettingsColumn: some View {"
        )
        let secondaryColumn = try sourceFragment(
            in: source,
            from: "    private var secondarySettingsColumn: some View {",
            to: "    private var shortcutsSection: some View {"
        )

        let superRightClickRange = try XCTUnwrap(primaryColumn.range(of: "superRightClickSection"))
        let permissionsRange = try XCTUnwrap(primaryColumn.range(of: "permissionsSection"))

        XCTAssertLessThan(superRightClickRange.lowerBound, permissionsRange.lowerBound)
        XCTAssertFalse(secondaryColumn.contains("permissionsSection"))
    }

    private func settingsViewSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/MacToolsCore/UI/SettingsView.swift"),
            encoding: .utf8
        )
    }

    private func sourceFragment(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }
}
