import CoreGraphics
import ImageIO
import XCTest
@testable import MacToolsCore

final class ScreenshotRendererTests: XCTestCase {
    func testRendererProducesPNGWithAllSupportedAnnotationTypes() throws {
        let data = try ScreenshotRenderer.pngData(
            image: try makeTestImage(),
            annotations: [
                .line(start: CGPoint(x: 2, y: 12), end: CGPoint(x: 26, y: 12), color: .red),
                .arrow(start: CGPoint(x: 2, y: 2), end: CGPoint(x: 20, y: 20), color: .green),
                .rectangle(CGRect(x: 4, y: 4, width: 10, height: 8), color: .blue),
                .circle(CGRect(x: 6, y: 10, width: 14, height: 14), color: .purple),
                .mosaic(CGRect(x: 16, y: 16, width: 8, height: 8))
            ]
        )

        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 32)
    }

    func testMosaicImageActuallyPixelatesSourcePixels() throws {
        let original = try makeCheckerboardImage()
        let mosaic = try ScreenshotRenderer.mosaicImage(image: original)
        let originalPixels = try rgbaPixels(of: original)
        let mosaicPixels = try rgbaPixels(of: mosaic)

        XCTAssertNotEqual(mosaicPixels, originalPixels)

        let mosaicRect = CGRect(x: 8, y: 40, width: 16, height: 16)
        let data = try ScreenshotRenderer.pngData(
            image: original,
            annotations: [.mosaic(mosaicRect)]
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let rendered = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let renderedPixels = try rgbaPixels(of: rendered)

        XCTAssertTrue(
            regionsDiffer(
                originalPixels,
                renderedPixels,
                width: 64,
                rect: mosaicRect
            )
        )
        XCTAssertFalse(
            regionsDiffer(
                originalPixels,
                renderedPixels,
                width: 64,
                rect: CGRect(x: 8, y: 8, width: 16, height: 16)
            )
        )
    }

    func testRendererDrawsRectangleAndCircleUsingSelectedColors() throws {
        let data = try ScreenshotRenderer.pngData(
            image: try makeSolidImage(color: CGColor(gray: 0, alpha: 1)),
            annotations: [
                .rectangle(CGRect(x: 3, y: 3, width: 26, height: 26), color: .red),
                .circle(CGRect(x: 8, y: 8, width: 16, height: 16), color: .green)
            ]
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try rgbaPixels(of: image)

        XCTAssertTrue(containsRGB(in: pixels) { red, green, blue in
            red > 180 && green < 100 && blue < 100
        })
        XCTAssertTrue(containsRGB(in: pixels) { red, green, blue in
            green > 140 && red < 100 && blue < 100
        })
    }

    func testRendererUsesEachAnnotationsSelectedLineWidth() throws {
        let image = try makeSolidImage(color: CGColor(gray: 0, alpha: 1))
        let thinData = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [
                .line(
                    start: CGPoint(x: 2, y: 16),
                    end: CGPoint(x: 30, y: 16),
                    color: .red,
                    lineWidth: 2
                )
            ]
        )
        let thickData = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [
                .line(
                    start: CGPoint(x: 2, y: 16),
                    end: CGPoint(x: 30, y: 16),
                    color: .red,
                    lineWidth: 8
                )
            ]
        )

        XCTAssertGreaterThan(
            try coloredPixelCount(in: thickData),
            try coloredPixelCount(in: thinData)
        )
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

    private func makeCheckerboardImage() throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 64,
            height: 64,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }

        for y in stride(from: 0, to: 64, by: 2) {
            for x in stride(from: 0, to: 64, by: 2) {
                let isRed = ((x + y) / 2).isMultiple(of: 2)
                context.setFillColor(
                    isRed
                        ? CGColor(red: 1, green: 0, blue: 0, alpha: 1)
                        : CGColor(red: 0, green: 0, blue: 1, alpha: 1)
                )
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func makeSolidImage(color: CGColor) throws -> CGImage {
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

        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return try XCTUnwrap(context.makeImage())
    }

    private func rgbaPixels(of image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let created = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard created else {
            throw TestImageError.contextCreationFailed
        }
        return pixels
    }

    private func containsRGB(
        in pixels: [UInt8],
        matching predicate: (UInt8, UInt8, UInt8) -> Bool
    ) -> Bool {
        var index = 0
        while index + 2 < pixels.count {
            if predicate(pixels[index], pixels[index + 1], pixels[index + 2]) {
                return true
            }
            index += 4
        }
        return false
    }

    private func coloredPixelCount(in data: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try rgbaPixels(of: image)
        var count = 0
        var index = 0
        while index + 2 < pixels.count {
            if pixels[index] > 120 && pixels[index + 1] < 100 && pixels[index + 2] < 100 {
                count += 1
            }
            index += 4
        }
        return count
    }

    private func regionsDiffer(
        _ lhs: [UInt8],
        _ rhs: [UInt8],
        width: Int,
        rect: CGRect
    ) -> Bool {
        let rect = rect.integral
        let height = lhs.count / (width * 4)
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let row = height - 1 - y
                let index = (row * width + x) * 4
                if lhs[index..<(index + 4)] != rhs[index..<(index + 4)] {
                    return true
                }
            }
        }
        return false
    }

    private enum TestImageError: Error {
        case contextCreationFailed
    }
}
