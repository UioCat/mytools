import CoreGraphics
import ImageIO
import XCTest
@testable import MacToolsCore

final class ScreenshotRendererTests: XCTestCase {
    func testRendererProducesPNGWithAllSupportedAnnotationTypes() throws {
        let data = try ScreenshotRenderer.pngData(
            image: try makeTestImage(),
            annotations: [
                .line(start: CGPoint(x: 2, y: 12), end: CGPoint(x: 26, y: 12)),
                .arrow(start: CGPoint(x: 2, y: 2), end: CGPoint(x: 20, y: 20)),
                .rectangle(CGRect(x: 4, y: 4, width: 10, height: 8)),
                .mosaic(CGRect(x: 16, y: 16, width: 8, height: 8))
            ]
        )

        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 32)
    }

    private func makeTestImage() throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 32,
            height: 32,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }

        context.setFillColor(CGColor(red: 0.15, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.setFillColor(CGColor(red: 0.9, green: 0.35, blue: 0.15, alpha: 1))
        context.fill(CGRect(x: 16, y: 16, width: 8, height: 8))

        return try XCTUnwrap(context.makeImage())
    }

    private enum TestImageError: Error {
        case contextCreationFailed
    }
}
