import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class AppEnvironmentStoreConfigurationTests: XCTestCase {
    func testUIVerificationUsesExplicitIsolatedDirectoryAndDisablesRecordingAndSync() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isolated = root.appendingPathComponent("isolated", isDirectory: true)
        let configuration = AppEnvironmentStoreConfiguration.make(
            defaultDirectory: root.appendingPathComponent("normal", isDirectory: true),
            arguments: ["MacTools", "--ui-verification-open-settings"],
            environment: ["MACTOOLS_UI_VERIFICATION_DIRECTORY": isolated.path]
        )
        var settings = AppSettings.defaults
        settings.sync.isEnabled = true
        let initial = configuration.initialSettings(settings)

        XCTAssertEqual(configuration.supportDirectory, isolated)
        XCTAssertTrue(configuration.isUIVerification)
        XCTAssertFalse(initial.clipboard.isRecordingEnabled)
        XCTAssertFalse(initial.sync.isEnabled)
    }

    func testNormalLaunchIgnoresVerificationEnvironmentVariable() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let normal = root.appendingPathComponent("normal", isDirectory: true)
        let configuration = AppEnvironmentStoreConfiguration.make(
            defaultDirectory: normal,
            arguments: ["MacTools"],
            environment: ["MACTOOLS_UI_VERIFICATION_DIRECTORY": root.appendingPathComponent("isolated").path]
        )
        XCTAssertEqual(configuration.supportDirectory, normal)
        XCTAssertFalse(configuration.isUIVerification)
        XCTAssertEqual(configuration.initialSettings(.defaults), .defaults)
    }

    func testRelativeVerificationDirectoryIsNotAcceptedAsIsolation() {
        let normal = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = AppEnvironmentStoreConfiguration.make(
            defaultDirectory: normal,
            arguments: ["MacTools", "--ui-verification-dark"],
            environment: ["MACTOOLS_UI_VERIFICATION_DIRECTORY": "relative-fixture"]
        )
        XCTAssertEqual(configuration.supportDirectory, normal)
        XCTAssertFalse(configuration.isUIVerification)
    }
}
