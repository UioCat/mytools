import XCTest
@testable import MacToolsCore

final class MainWorkspaceTests: XCTestCase {
    func testSettingsIsTheDefaultMainModule() {
        XCTAssertEqual(MainToolModule.defaultModule, .settings)
        XCTAssertEqual(MainToolModule.allCases.first, .settings)
    }

    func testEscapeKeyMapsToDismissForEveryMainModule() {
        let resolver = PanelKeyCommandResolver()

        XCTAssertEqual(resolver.command(forKeyCode: 53), .dismiss)
        XCTAssertNil(resolver.command(forKeyCode: 36))
    }
}
