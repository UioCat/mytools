import AppKit
import XCTest
@testable import MacToolsCore

final class ContextPanelWindowAppearanceTests: XCTestCase {
    func testContextPanelHasNoTitledChromeOrRectangularSystemShadow() {
        let styleMask = ContextPanelWindowAppearance.windowStyleMask

        XCTAssertFalse(styleMask.contains(.titled))
        XCTAssertFalse(styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(ContextPanelWindowAppearance.usesSystemWindowShadow)
        XCTAssertEqual(ContextPanelWindowAppearance.windowCornerRadius, 22)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 210),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        XCTAssertNil(panel.standardWindowButton(.closeButton))
    }

    func testContextPanelBackingLayerClipsOutsideTheRoundedGlassShape() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 210))

        ContextPanelWindowAppearance.configureRoundedBackingLayer(view)

        let layer = try XCTUnwrap(view.layer)
        XCTAssertEqual(layer.cornerRadius, 22)
        XCTAssertEqual(layer.cornerCurve, .continuous)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertEqual(layer.backgroundColor, NSColor.clear.cgColor)
    }
}
