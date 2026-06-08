import AppKit
import XCTest
@testable import MacToolsCore

final class MainPanelControllerTests: XCTestCase {
    func testMainPanelStyleAvoidsTransparentTitlebarAppSpace() {
        let styleMask = MainPanelController.windowStyleMask

        XCTAssertFalse(styleMask.contains(.titled))
        XCTAssertFalse(styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(styleMask.contains(.resizable))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        XCTAssertNil(panel.standardWindowButton(.closeButton))
    }
}
