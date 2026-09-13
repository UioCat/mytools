import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenCaptureSnapshotTests: XCTestCase {
    func testCropPreservesTopLeftPopupPixelsOnOffsetRetinaDisplay() throws {
        let frame = CGRect(x: -100, y: 50, width: 100, height: 80)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 20, y: 120, width: 40, height: 20))
        let snapshot = ScreenCaptureSnapshot(displayID: 7, displayFrame: frame,
                                             image: try XCTUnwrap(context.makeImage()))
        // Simulate the popup disappearing on the live desktop after capture.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 160))
        let selection = ScreenCaptureSelection(displayID: 7, displayFrame: frame,
            rawSelectionFrame: CGRect(x: -90, y: 110, width: 20, height: 10))
        let crop = try XCTUnwrap(snapshot.croppedImage(for: selection))
        XCTAssertEqual(crop.width, 40)
        XCTAssertEqual(crop.height, 20)
        let pixel = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        pixel.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try XCTUnwrap(pixel.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(bytes[0], 255)
        XCTAssertEqual(bytes[2], 0)
        XCTAssertNil(snapshot.croppedImage(for: ScreenCaptureSelection(
            displayID: 8, displayFrame: frame, rawSelectionFrame: selection.frame)))
        XCTAssertNil(snapshot.croppedImage(for: ScreenCaptureSelection(
            displayID: 7, displayFrame: frame.offsetBy(dx: 1, dy: 0), rawSelectionFrame: selection.frame)))
    }
}
