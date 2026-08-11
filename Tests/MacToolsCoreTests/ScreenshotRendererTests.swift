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
                .freehand(
                    points: [CGPoint(x: 4, y: 20), CGPoint(x: 12, y: 26), CGPoint(x: 24, y: 18)],
                    color: .purple
                ),
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

    func testRendererDrawsRectangleAndFreehandUsingSelectedColors() throws {
        let data = try ScreenshotRenderer.pngData(
            image: try makeSolidImage(color: CGColor(gray: 0, alpha: 1)),
            annotations: [
                .rectangle(CGRect(x: 3, y: 3, width: 26, height: 26), color: .red),
                .freehand(
                    points: [CGPoint(x: 4, y: 8), CGPoint(x: 16, y: 22), CGPoint(x: 28, y: 10)],
                    color: .green,
                    lineWidth: 4
                )
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
        for point in [
            CGPoint(x: 4, y: 8),
            CGPoint(x: 10, y: 15),
            CGPoint(x: 16, y: 22),
            CGPoint(x: 22, y: 16),
            CGPoint(x: 28, y: 10)
        ] {
            let pixel = rgb(at: point, in: pixels, width: image.width, height: image.height)
            XCTAssertGreaterThan(pixel.green, 140, "Expected freehand stroke at \(point)")
            XCTAssertLessThan(pixel.red, 100, "Expected freehand stroke at \(point)")
        }
        let offPathPixel = rgb(
            at: CGPoint(x: 16, y: 5),
            in: pixels,
            width: image.width,
            height: image.height
        )
        XCTAssertLessThan(offPathPixel.green, 30)
    }

    func testRendererUsesSelectedFreehandLineWidthAcrossFullPath() throws {
        let image = try makeSolidImage(color: CGColor(gray: 0, alpha: 1))
        let points = [CGPoint(x: 3, y: 5), CGPoint(x: 16, y: 25), CGPoint(x: 29, y: 7)]
        let thinData = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [.freehand(points: points, color: .red, lineWidth: 2)]
        )
        let thickData = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [.freehand(points: points, color: .red, lineWidth: 8)]
        )

        XCTAssertGreaterThan(
            try coloredPixelCount(in: thickData),
            try coloredPixelCount(in: thinData)
        )
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

    func testRendererDrawsMultilineTextUsingSelectedColor() throws {
        let image = try makeSolidImage(
            width: 180,
            height: 100,
            color: CGColor(gray: 0, alpha: 1)
        )
        let data = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [
                .text(
                    text: "第一行\nSecond line",
                    frame: CGRect(x: 12, y: 16, width: 150, height: 64),
                    color: .red,
                    fontSize: 20
                )
            ]
        )

        XCTAssertGreaterThan(try coloredPixelCount(in: data), 40)
    }

    func testRendererDrawsLabelBubbleAndIndependentLocatorColor() throws {
        let image = try makeSolidImage(
            width: 220,
            height: 100,
            color: CGColor(gray: 0.8, alpha: 1)
        )
        let data = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [
                .label(
                    text: "重点区域",
                    anchor: CGPoint(x: 24, y: 50),
                    direction: .left,
                    color: .red,
                    fontSize: 18,
                    maximumWidth: 160
                )
            ]
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let rendered = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try rgbaPixels(of: rendered)
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: "重点区域",
            anchor: CGPoint(x: 24, y: 50),
            direction: .left,
            fontSize: 18,
            maximumWidth: 160
        )
        let locator = rgb(at: CGPoint(x: 24, y: 50), in: pixels, width: rendered.width, height: rendered.height)
        let bubble = rgb(
            at: CGPoint(x: geometry.bubbleRect.minX + 3, y: geometry.bubbleRect.midY),
            in: pixels,
            width: rendered.width,
            height: rendered.height
        )

        XCTAssertGreaterThan(locator.red, 180)
        XCTAssertLessThan(locator.green, 100)
        XCTAssertLessThan(locator.blue, 100)
        XCTAssertGreaterThan(bubble.red, 220)
        XCTAssertGreaterThan(bubble.green, 220)
        XCTAssertGreaterThan(bubble.blue, 215)
    }

    func testRendererClipsLegacyLabelTextToAnEllipsisSizedTextRect() throws {
        let image = try makeSolidImage(
            width: 180,
            height: 100,
            color: CGColor(gray: 0.8, alpha: 1)
        )
        let common: (String) -> ScreenshotAnnotation = { text in
            .label(
                text: text,
                anchor: CGPoint(x: 24, y: 50),
                direction: .left,
                color: .red,
                fontSize: 24,
                maximumWidth: 1
            )
        }
        let longLabel = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [common("这是一段放不下的完整标签文字")]
        )
        let ellipsisLabel = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [common("…")]
        )

        let longPixels = try rgbaPixels(in: longLabel)
        let ellipsisPixels = try rgbaPixels(in: ellipsisLabel)
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: "这是一段放不下的完整标签文字",
            anchor: CGPoint(x: 24, y: 50),
            direction: .left,
            fontSize: 24,
            maximumWidth: 1
        )
        XCTAssertGreaterThanOrEqual(
            geometry.textRect.width,
            ScreenshotTextLayout.minimumSingleLineTruncationWidth(fontSize: 24)
        )
        XCTAssertFalse(
            regionsDifferOutside(
                longPixels,
                ellipsisPixels,
                width: image.width,
                allowedRect: geometry.textRect.insetBy(dx: -1, dy: -1)
            )
        )
    }

    func testLabelStyleSnapshotShowsAdaptiveLabelsOnLightAndDarkBackgrounds() throws {
        let image = try makeLabelPreviewImage(width: 900, height: 500)
        let data = try ScreenshotRenderer.pngData(
            image: image,
            annotations: [
                .label(
                    text: "hello",
                    anchor: CGPoint(x: 64, y: 120),
                    direction: .left,
                    color: .red,
                    fontSize: 24,
                    maximumWidth: 780
                ),
                .label(
                    text: "文字水平与垂直居中",
                    anchor: CGPoint(x: 64, y: 250),
                    direction: .left,
                    color: .blue,
                    fontSize: 24,
                    maximumWidth: 780
                ),
                .label(
                    text: "宽度会随着这段文字自然增长，不再提前缩进",
                    anchor: CGPoint(x: 836, y: 380),
                    direction: .right,
                    color: .green,
                    fontSize: 24,
                    maximumWidth: 780
                )
            ]
        )

        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        if let outputDirectory = ProcessInfo.processInfo.environment["MACTOOLS_SCREENSHOT_LABEL_SNAPSHOT_DIR"] {
            let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: directoryURL.appendingPathComponent("screenshot-label-style.png"))
        }
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

    private func makeLabelPreviewImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 0.92, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
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
        try makeSolidImage(width: 32, height: 32, color: color)
    }

    private func makeSolidImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }

        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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

    private func rgbaPixels(in data: Data) throws -> [UInt8] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try rgbaPixels(
            of: XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        )
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

    private func rgb(
        at point: CGPoint,
        in pixels: [UInt8],
        width: Int,
        height: Int
    ) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let x = min(max(Int(point.x), 0), width - 1)
        let y = min(max(Int(point.y), 0), height - 1)
        let row = height - 1 - y
        let index = (row * width + x) * 4
        return (pixels[index], pixels[index + 1], pixels[index + 2])
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

    private func regionsDifferOutside(
        _ lhs: [UInt8],
        _ rhs: [UInt8],
        width: Int,
        allowedRect: CGRect
    ) -> Bool {
        let height = lhs.count / (width * 4)
        for y in 0..<height {
            for x in 0..<width {
                guard !allowedRect.contains(CGPoint(x: x, y: y)) else {
                    continue
                }
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
