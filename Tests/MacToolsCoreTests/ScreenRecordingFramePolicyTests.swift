import ScreenCaptureKit
import XCTest
@testable import MacToolsCore

final class ScreenRecordingFramePolicyTests: XCTestCase {
    func testOnlyCompleteFramesWithImageDataAreAppended() {
        XCTAssertTrue(
            ScreenRecordingFramePolicy.shouldAppend(
                frameStatus: .complete,
                hasImageBuffer: true
            )
        )
        XCTAssertFalse(
            ScreenRecordingFramePolicy.shouldAppend(
                frameStatus: .complete,
                hasImageBuffer: false
            )
        )
        XCTAssertFalse(
            ScreenRecordingFramePolicy.shouldAppend(
                frameStatus: .idle,
                hasImageBuffer: true
            )
        )
        XCTAssertFalse(
            ScreenRecordingFramePolicy.shouldAppend(
                frameStatus: .blank,
                hasImageBuffer: true
            )
        )
    }

    func testRecordingCompletesOnlyWhenWriterAndCaptureFinishWithoutErrors() {
        XCTAssertTrue(
            ScreenRecordingCompletionPolicy.isSuccessful(
                writerCompleted: true,
                hasRecordedFailure: false,
                hasCaptureStopError: false
            )
        )
        XCTAssertFalse(
            ScreenRecordingCompletionPolicy.isSuccessful(
                writerCompleted: true,
                hasRecordedFailure: true,
                hasCaptureStopError: false
            )
        )
        XCTAssertFalse(
            ScreenRecordingCompletionPolicy.isSuccessful(
                writerCompleted: true,
                hasRecordedFailure: false,
                hasCaptureStopError: true
            )
        )
        XCTAssertFalse(
            ScreenRecordingCompletionPolicy.isSuccessful(
                writerCompleted: false,
                hasRecordedFailure: false,
                hasCaptureStopError: false
            )
        )
    }
}
