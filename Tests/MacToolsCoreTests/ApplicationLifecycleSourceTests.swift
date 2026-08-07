import Foundation
import XCTest

final class ApplicationLifecycleSourceTests: XCTestCase {
    func testApplicationRetainsDelegateForEntireEventLoop() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/MacTools/Application/MacToolsMain.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("withExtendedLifetime(delegate)"))
        XCTAssertTrue(source.contains("app.run()"))
    }

    func testVerificationArgumentCanStartARealUpdateCheck() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let delegateSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/MacTools/Application/AppDelegate.swift"),
            encoding: .utf8
        )
        let environmentSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/MacTools/Application/AppEnvironment.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(delegateSource.contains("--ui-verification-check-for-updates"))
        XCTAssertTrue(environmentSource.contains("checkForUpdatesForUIVerification"))
    }
}
