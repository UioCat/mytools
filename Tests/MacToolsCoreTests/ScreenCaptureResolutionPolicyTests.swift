import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenCaptureResolutionPolicyTests: XCTestCase {
    func testScreenshotUsesNativePointPixelScale() {
        let size = ScreenCaptureResolutionPolicy.outputPixelSize(
            for: CGSize(width: 400, height: 300),
            pointPixelScale: 2,
            purpose: .screenshot
        )

        XCTAssertEqual(size, CGSize(width: 800, height: 600))
    }

    func testRecordingKeepsOnePointPerPixel() {
        let size = ScreenCaptureResolutionPolicy.outputPixelSize(
            for: CGSize(width: 400, height: 300),
            pointPixelScale: 2,
            purpose: .recording
        )

        XCTAssertEqual(size, CGSize(width: 400, height: 300))
    }

    func testOutputPixelSizeRoundsAndNeverReturnsZero() {
        let size = ScreenCaptureResolutionPolicy.outputPixelSize(
            for: CGSize(width: 0.2, height: 100.4),
            pointPixelScale: 2,
            purpose: .screenshot
        )

        XCTAssertEqual(size, CGSize(width: 1, height: 201))
    }
}
