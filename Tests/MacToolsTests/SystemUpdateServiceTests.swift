import Foundation
import XCTest
@testable import MacTools

final class SystemUpdateServiceTests: XCTestCase {
    @MainActor
    func testBundleWithoutFeedIsUnavailableRatherThanChecking() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Synthetic.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.synthetic.updates", "CFBundleShortVersionString": "1.2.3"],
            format: .xml, options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root.appendingPathComponent("Synthetic.app")))
        let service = SystemUpdateService(bundle: bundle)

        XCTAssertEqual(service.state.version, "1.2.3")
        XCTAssertFalse(service.state.isAvailable)
        XCTAssertFalse(service.state.isCheckingForUpdates)
        service.checkForUpdates()
        service.setAutomaticallyChecksForUpdates(true)
        XCTAssertFalse(service.state.automaticallyChecksForUpdates)
    }
}
