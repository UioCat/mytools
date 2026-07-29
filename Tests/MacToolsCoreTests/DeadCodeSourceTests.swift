import Foundation
import XCTest

final class DeadCodeSourceTests: XCTestCase {
    func testRemovedCloudAccountSwitchCallbackIsNotPropagatedThroughRuntimeViews() throws {
        for path in [
            "Sources/MacTools/Application/AppEnvironment.swift",
            "Sources/MacTools/Application/RuntimeViews.swift",
            "Sources/MacToolsCore/UI/Settings/SettingsView.swift"
        ] {
            let source = try sourceFile(path)
            XCTAssertFalse(source.contains("confirmCloudAccountSwitch"), path)
            XCTAssertFalse(source.contains("onConfirmCloudAccountSwitch"), path)
        }
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
