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
    private static let mosaicScale: CGFloat = 12
    private static let ciContext = CIContext(options: nil)

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
        let mosaicImage = try annotations.contains(where: isMosaic)
            ? mosaicImage(image: image)
            : nil

        for annotation in annotations {
            switch annotation {
            case let .line(start, end, color, lineWidth):
                drawLine(in: context, start: start, end: end, color: color, lineWidth: lineWidth)
            case let .arrow(start, end, color, lineWidth):
                drawArrow(in: context, start: start, end: end, color: color, lineWidth: lineWidth)
            case let .rectangle(rect, color, lineWidth):
                drawRectangle(in: context, rect: rect, color: color, lineWidth: lineWidth)
            case let .circle(rect, color, lineWidth):
                drawCircle(in: context, rect: rect, color: color, lineWidth: lineWidth)
            case let .mosaic(rect):
                if let mosaicImage {
                    drawMosaic(in: context, mosaicImage: mosaicImage, rect: rect, bounds: bounds)
                }
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

    public static func mosaicImage(image: CGImage) throws -> CGImage {
        try makeMosaicImage(
            sourceImage: image,
            bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
    }

    private static func drawLine(
        in context: CGContext,
        start: CGPoint,
        end: CGPoint,
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrow(
        in context: CGContext,
        start: CGPoint,
        end: CGPoint,
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat
    ) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowHeadLength = ScreenshotAnnotationArrowStyle.headLength(forLineWidth: lineWidth)
        let headLeft = CGPoint(
            x: end.x - arrowHeadLength * cos(angle - .pi / 6),
            y: end.y - arrowHeadLength * sin(angle - .pi / 6)
        )
        let headRight = CGPoint(
            x: end.x - arrowHeadLength * cos(angle + .pi / 6),
            y: end.y - arrowHeadLength * sin(angle + .pi / 6)
        )

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
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

    private static func drawRectangle(
        in context: CGContext,
        rect: CGRect,
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.stroke(rect.standardized)
        context.restoreGState()
    }

    private static func drawCircle(
        in context: CGContext,
        rect: CGRect,
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: rect.standardized)
        context.restoreGState()
    }

    private static func makeMosaicImage(sourceImage: CGImage, bounds: CGRect) throws -> CGImage {
        guard let filter = CIFilter(name: "CIPixellate") else {
            throw ScreenshotRendererError.mosaicFilterUnavailable
        }

        filter.setValue(CIImage(cgImage: sourceImage), forKey: kCIInputImageKey)
        filter.setValue(mosaicScale, forKey: kCIInputScaleKey)
        guard let outputImage = filter.outputImage else {
            throw ScreenshotRendererError.mosaicFilterUnavailable
        }

        guard let mosaicImage = ciContext.createCGImage(
            outputImage.cropped(to: bounds),
            from: bounds
        ) else {
            throw ScreenshotRendererError.contextCreationFailed
        }

        return mosaicImage
    }

    private static func drawMosaic(
        in context: CGContext,
        mosaicImage: CGImage,
        rect: CGRect,
        bounds: CGRect
    ) {
        let mosaicRect = rect.standardized.intersection(bounds).integral
        guard !mosaicRect.isEmpty else {
            return
        }

        context.saveGState()
        context.clip(to: mosaicRect)
        context.draw(mosaicImage, in: bounds)
        context.restoreGState()
    }

    private static func isMosaic(_ annotation: ScreenshotAnnotation) -> Bool {
        if case .mosaic = annotation {
            return true
        }
        return false
    }
}
