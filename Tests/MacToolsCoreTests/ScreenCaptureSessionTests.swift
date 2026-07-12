import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenCaptureSessionTests: XCTestCase {
    func testSessionCannotStartRecordingWithoutAValidSelection() {
        var state = ScreenCaptureSessionState.idle

        XCTAssertFalse(state.beginRecording())
        XCTAssertEqual(state, .idle)
    }

    func testSessionStartsScreenshotOnlyAfterAcceptingSelection() {
        var state = ScreenCaptureSessionState.idle
        let selection = ScreenCaptureSelection(
            displayID: 7,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rawSelectionFrame: CGRect(x: 10, y: 10, width: 50, height: 50)
        )

        state.beginSelection()

        XCTAssertTrue(state.acceptSelection(selection))
        XCTAssertTrue(state.beginScreenshot())
        XCTAssertEqual(state, .capturingScreenshot)
    }

    func testRecordingStateTransitionsToFinishedWhenStopped() {
        var state = ScreenCaptureSessionState.idle
        let selection = ScreenCaptureSelection(
            displayID: 7,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            rawSelectionFrame: CGRect(x: 10, y: 10, width: 40, height: 40)
        )

        XCTAssertTrue(state.acceptSelection(selection))
        XCTAssertTrue(state.beginRecording())

        state.finish()

        XCTAssertEqual(state, .finished)
    }
}
