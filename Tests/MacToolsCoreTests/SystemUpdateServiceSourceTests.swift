import Foundation
import XCTest

final class SystemUpdateServiceSourceTests: XCTestCase {
    func testPlatformServiceOwnsSparkleAndPublishesCoreSnapshot() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/Updates/SystemUpdateService.swift"
        )

        XCTAssertTrue(source.contains("import Sparkle"))
        XCTAssertTrue(source.contains("SPUStandardUpdaterController"))
        XCTAssertTrue(source.contains("@Published private(set) var state"))
        XCTAssertTrue(source.contains("updaterController.checkForUpdates(nil)"))
        XCTAssertTrue(source.contains("updater.automaticallyChecksForUpdates = isEnabled"))
        XCTAssertTrue(source.contains("updater.automaticallyDownloadsUpdates = isEnabled"))
    }

    func testRuntimeInjectsUpdateServiceIntoCoreSettingsView() throws {
        let source = try sourceFile("Sources/MacTools/Application/RuntimeViews.swift")

        XCTAssertTrue(source.contains("softwareUpdateState: softwareUpdateService.state"))
        XCTAssertTrue(source.contains("checkForUpdates: softwareUpdateService.checkForUpdates"))
        XCTAssertTrue(
            source.contains(
                "setAutomaticallyChecksForUpdates: softwareUpdateService.setAutomaticallyChecksForUpdates"
            )
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
