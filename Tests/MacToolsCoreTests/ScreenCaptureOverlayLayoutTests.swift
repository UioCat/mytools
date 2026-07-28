import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenCaptureOverlayLayoutTests: XCTestCase {
    func testDefaultCaptureModeIsScreenshot() {
        XCTAssertEqual(ScreenCaptureMode.default, .screenshot)
    }

    func testModeToolbarIsPinnedToTopCenterOfDisplay() {
        let frame = ScreenCaptureOverlayLayout.modeToolbarFrame(
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 622, y: 840, width: 196, height: 44))
    }

    func testEditorToolbarPrefersBelowSelectionAndStaysInsideDisplay() {
        let frame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: CGRect(x: 120, y: 240, width: 700, height: 400),
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 160, width: 720, height: 68))
    }

    func testEditorToolbarMovesAboveLowSelectionAndClampsHorizontally() {
        let frame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: CGRect(x: 1_298, y: 8, width: 140, height: 120),
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 708, y: 140, width: 720, height: 68))
    }

    func testEditorToolbarShrinksToStayInsideANarrowDisplay() {
        let frame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: CGRect(x: 40, y: 100, width: 300, height: 240),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 700)
        )

        XCTAssertEqual(frame, CGRect(x: 12, y: 20, width: 476, height: 68))
    }

    func testRecordingControlIsPinnedToTopCenterOfSelectedDisplay() {
        let frame = ScreenCaptureOverlayLayout.recordingControlFrame(
            visibleFrame: CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: -808, y: 836, width: 176, height: 48))
    }

    func testRecordingControlStaysBelowMenuBarAndCentersInVisibleFrame() {
        let frame = ScreenCaptureOverlayLayout.recordingControlFrame(
            visibleFrame: CGRect(x: 80, y: 40, width: 1_360, height: 836)
        )

        XCTAssertEqual(frame, CGRect(x: 672, y: 812, width: 176, height: 48))
    }
}
