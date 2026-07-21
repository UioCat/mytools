import Foundation
import XCTest

final class PackageAppScriptTests: XCTestCase {
    func testPackageScriptDeclaresFinderAppleEventsUsageDescription() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("<key>NSAppleEventsUsageDescription</key>"))
        XCTAssertTrue(script.contains("<string>用于读取访达当前窗口目录，以显示超级右键的目录操作。</string>"))
    }

    func testPackageScriptDeclaresAndCopiesApplicationIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(
            script.contains("Sources/MacTools/Resources/AppIcon.icns")
        )
        XCTAssertTrue(script.contains("<key>CFBundleIconFile</key>"))
        XCTAssertTrue(script.contains("<string>AppIcon.icns</string>"))
    }

    func testPackageScriptDoesNotRequireCloudKitEntitlementsOrProvisioningProfile() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertFalse(script.contains("MACOS_ENABLE_CLOUDKIT"))
        XCTAssertFalse(script.contains("MacToolsCloudSyncAvailable"))
        XCTAssertFalse(script.contains("MACOS_ICLOUD_CONTAINER_ID"))
        XCTAssertFalse(script.contains("MACOS_PROVISIONING_PROFILE"))
        XCTAssertFalse(script.contains("--entitlements"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("scripts/MacTools.entitlements").path
        ))
    }

    func testPackageScriptKeepsAdHocSigningPath() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = repositoryRoot.appendingPathComponent("scripts/package_app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(script.contains("MACOS_FORCE_ADHOC_SIGNING"))
        XCTAssertTrue(script.contains("using ad-hoc signing"))
        XCTAssertTrue(script.contains("--sign -"))
    }
}
