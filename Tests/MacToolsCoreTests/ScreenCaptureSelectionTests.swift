import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenCaptureSelectionTests: XCTestCase {
    func testSelectionNormalizesReverseDragAndClampsToOriginatingDisplay() {
        let selection = ScreenCaptureSelection(
            displayID: 7,
            displayFrame: CGRect(x: 100, y: 100, width: 800, height: 600),
            rawSelectionFrame: CGRect(x: 950, y: 750, width: -900, height: -700)
        )

        XCTAssertEqual(selection.frame, CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertTrue(selection.isValid)
    }

    func testSelectionRejectsTinyRectangle() {
        let selection = ScreenCaptureSelection(
            displayID: 7,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rawSelectionFrame: CGRect(x: 20, y: 20, width: 7, height: 7)
        )

        XCTAssertFalse(selection.isValid)
    }

    func testSelectionConvertsAppKitFrameToScreenCaptureKitSourceCoordinates() {
        let selection = ScreenCaptureSelection(
            displayID: 7,
            displayFrame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            rawSelectionFrame: CGRect(x: 280, y: 140, width: 1_300, height: 1_226)
        )

        XCTAssertEqual(
            selection.screenCaptureKitSourceFrame,
            CGRect(x: 280, y: 74, width: 1_300, height: 1_226)
        )
    }

    func testScreenCaptureKitSourceCoordinatesIgnoreGlobalDisplayOrigin() {
        let selection = ScreenCaptureSelection(
            displayID: 8,
            displayFrame: CGRect(x: -1_440, y: 200, width: 1_440, height: 900),
            rawSelectionFrame: CGRect(x: -1_340, y: 300, width: 500, height: 240)
        )

        XCTAssertEqual(
            selection.screenCaptureKitSourceFrame,
            CGRect(x: 100, y: 560, width: 500, height: 240)
        )
    }
}
