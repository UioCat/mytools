import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScreenshotRendererError: Error, Equatable {
    case contextCreationFailed
    case imageEncodingFailed
    case mosaicFilterUnavailable
}

public enum ScreenshotRenderer {
    private static let strokeColor = CGColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    private static let strokeWidth: CGFloat = 3
    private static let arrowHeadLength: CGFloat = 10
    private static let mosaicScale: CGFloat = 12

    public static func pngData(image: CGImage, annotations: [ScreenshotAnnotation]) throws -> Data {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotRendererError.contextCreationFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: bounds)

        for annotation in annotations {
            switch annotation {
            case let .line(start, end):
                drawLine(in: context, start: start, end: end)
            case let .arrow(start, end):
                drawArrow(in: context, start: start, end: end)
            case let .rectangle(rect):
                drawRectangle(in: context, rect: rect)
            case let .mosaic(rect):
                try drawMosaic(in: context, sourceImage: image, rect: rect, bounds: bounds)
            }
        }

        guard let renderedImage = context.makeImage() else {
            throw ScreenshotRendererError.contextCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotRendererError.imageEncodingFailed
        }

        CGImageDestinationAddImage(destination, renderedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotRendererError.imageEncodingFailed
        }

        return data as Data
    }

    private static func drawLine(in context: CGContext, start: CGPoint, end: CGPoint) {
        context.saveGState()
        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrow(in context: CGContext, start: CGPoint, end: CGPoint) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLeft = CGPoint(
            x: end.x - arrowHeadLength * cos(angle - .pi / 6),
            y: end.y - arrowHeadLength * sin(angle - .pi / 6)
        )
        let headRight = CGPoint(
            x: end.x - arrowHeadLength * cos(angle + .pi / 6),
            y: end.y - arrowHeadLength * sin(angle + .pi / 6)
        )

        context.saveGState()
        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.addLine(to: headLeft)
        context.move(to: end)
        context.addLine(to: headRight)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawRectangle(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setStrokeColor(strokeColor)
        context.setLineWidth(strokeWidth)
        context.stroke(rect.standardized)
        context.restoreGState()
    }

    private static func drawMosaic(
        in context: CGContext,
        sourceImage: CGImage,
        rect: CGRect,
        bounds: CGRect
    ) throws {
        let mosaicRect = rect.standardized.intersection(bounds).integral
        guard !mosaicRect.isEmpty else {
            return
        }

        guard let filter = CIFilter(name: "CIPixellate") else {
            throw ScreenshotRendererError.mosaicFilterUnavailable
        }

        filter.setValue(CIImage(cgImage: sourceImage), forKey: kCIInputImageKey)
        filter.setValue(mosaicScale, forKey: kCIInputScaleKey)
        guard let outputImage = filter.outputImage else {
            throw ScreenshotRendererError.mosaicFilterUnavailable
        }

        let ciContext = CIContext(options: nil)
        guard let mosaicImage = ciContext.createCGImage(
            outputImage.cropped(to: mosaicRect),
            from: mosaicRect
        ) else {
            throw ScreenshotRendererError.contextCreationFailed
        }

        context.draw(mosaicImage, in: mosaicRect)
    }
}
