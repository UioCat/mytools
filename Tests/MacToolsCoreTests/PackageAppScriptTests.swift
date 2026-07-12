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
}
