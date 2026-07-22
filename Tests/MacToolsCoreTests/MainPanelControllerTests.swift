import AppKit
import XCTest
@testable import MacToolsCore

final class MainPanelControllerTests: XCTestCase {
    func testMainPanelCentersOnlyForItsFirstPresentation() {
        XCTAssertEqual(
            MainPanelPositioningPolicy.decision(hasExistingPanel: false),
            .center
        )
        XCTAssertEqual(
            MainPanelPositioningPolicy.decision(hasExistingPanel: true),
            .preserveCurrentFrame
        )
    }

    @MainActor
    func testMainPanelKeepsResizeWithoutRectangularSystemShadow() {
        let styleMask = MainPanelController.windowStyleMask

        XCTAssertFalse(styleMask.contains(.titled))
        XCTAssertFalse(styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(styleMask.contains(.resizable))
        XCTAssertFalse(MainPanelController.usesSystemWindowShadow)
        XCTAssertEqual(MainPanelController.windowCornerRadius, 40)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        XCTAssertNil(panel.standardWindowButton(.closeButton))
    }

    @MainActor
    func testRoundedBackingLayerClipsAppKitAndBackdropContent() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))

        MainPanelController.configureRoundedBackingLayer(view)

        let layer = try XCTUnwrap(view.layer)
        XCTAssertEqual(layer.cornerRadius, 40)
        XCTAssertEqual(layer.cornerCurve, .continuous)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertEqual(layer.backgroundColor, NSColor.clear.cgColor)
    }
}
