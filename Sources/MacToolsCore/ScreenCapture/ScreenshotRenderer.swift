// `ScreenshotRenderer` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 描述 `ScreenshotRendererError` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenshotRendererError: Error, Equatable {
    case contextCreationFailed
    case imageEncodingFailed
    case mosaicFilterUnavailable
}

/// 在位图上下文中合成截图标注，并编码最终 PNG。
public enum ScreenshotRenderer {
    private static let mosaicScale: CGFloat = 12
    private static let ciContext = CIContext(options: nil)

    /// 按标注顺序合成原图、线条、箭头、矩形和马赛克，并编码为 PNG。
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
        // 马赛克滤镜成本较高，整张图只生成一次，再通过 clip 复用到所有马赛克区域。
        let mosaicImage = try annotations.contains(where: isMosaic)
            ? mosaicImage(image: image)
            : nil

        for annotation in annotations {
            switch annotation {
            case let .line(start, end, color, lineWidth):
                drawLine(in: context, start: start, end: end, color: color, lineWidth: lineWidth)
            case let .freehand(points, color, lineWidth):
                drawFreehand(in: context, points: points, color: color, lineWidth: lineWidth)
            case let .arrow(start, end, color, lineWidth):
                drawArrow(in: context, start: start, end: end, color: color, lineWidth: lineWidth)
            case let .rectangle(rect, color, lineWidth):
                drawRectangle(in: context, rect: rect, color: color, lineWidth: lineWidth)
            case let .mosaic(rect):
                if let mosaicImage {
                    drawMosaic(in: context, mosaicImage: mosaicImage, rect: rect, bounds: bounds)
                }
            case let .text(text, frame, color, fontSize):
                drawText(
                    in: context,
                    text: text,
                    frame: frame,
                    color: color,
                    fontSize: fontSize
                )
            case let .label(text, anchor, direction, color, fontSize, maximumWidth):
                drawLabel(
                    in: context,
                    text: text,
                    anchor: anchor,
                    direction: direction,
                    color: color,
                    fontSize: fontSize,
                    maximumWidth: maximumWidth
                )
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

    /// 生成与原图像素尺寸一致的完整马赛克图，供编辑预览复用。
    public static func mosaicImage(image: CGImage) throws -> CGImage {
        try makeMosaicImage(
            sourceImage: image,
            bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
    }

    /// 在当前图形上下文中绘制 `drawLine` 指定的截图标注内容。
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

    /// 在当前图形上下文中绘制 `drawArrow` 指定的截图标注内容。
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

    /// 在当前图形上下文中绘制 `drawFreehand` 指定的截图标注内容。
    private static func drawFreehand(
        in context: CGContext,
        points: [CGPoint],
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat
    ) {
        guard let firstPoint = points.first else {
            return
        }

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if points.count == 1 {
            let radius = lineWidth / 2
            context.fillEllipse(
                in: CGRect(
                    x: firstPoint.x - radius,
                    y: firstPoint.y - radius,
                    width: lineWidth,
                    height: lineWidth
                )
            )
        } else {
            context.move(to: firstPoint)
            points.dropFirst().forEach(context.addLine)
            context.strokePath()
        }

        context.restoreGState()
    }

    /// 在当前图形上下文中绘制 `drawRectangle` 指定的截图标注内容。
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

    /// 构造并返回 `makeMosaicImage` 所描述的截图录屏核心领域对象。
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

    /// 在当前图形上下文中绘制 `drawMosaic` 指定的截图标注内容。
    private static func drawMosaic(
        in context: CGContext,
        mosaicImage: CGImage,
        rect: CGRect,
        bounds: CGRect
    ) {
        // 先裁剪到图像边界并对齐整数像素，避免 Core Graphics 读取越界或产生半像素接缝。
        let mosaicRect = rect.standardized.intersection(bounds).integral
        guard !mosaicRect.isEmpty else {
            return
        }

        context.saveGState()
        context.clip(to: mosaicRect)
        context.draw(mosaicImage, in: bounds)
        context.restoreGState()
    }

    private static func drawText(
        in context: CGContext,
        text: String,
        frame: CGRect,
        color: ScreenshotAnnotationColor,
        fontSize: CGFloat
    ) {
        guard !text.isEmpty, !frame.isEmpty else {
            return
        }
        let framesetter = CTFramesetterCreateWithAttributedString(
            ScreenshotTextLayout.attributedString(text: text, fontSize: fontSize, color: color.cgColor)
        )
        let path = CGPath(rect: frame.standardized, transform: nil)
        let textFrame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)

        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(textFrame, context)
        context.restoreGState()
    }

    private static func drawLabel(
        in context: CGContext,
        text: String,
        anchor: CGPoint,
        direction: ScreenshotLabelDirection,
        color: ScreenshotAnnotationColor,
        fontSize: CGFloat,
        maximumWidth: CGFloat
    ) {
        guard !text.isEmpty else {
            return
        }
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: text,
            anchor: anchor,
            direction: direction,
            fontSize: fontSize,
            maximumWidth: maximumWidth
        )
        let cornerRadius = min(geometry.cornerRadius, geometry.bubbleRect.height / 2)

        context.saveGState()
        context.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 0.94))
        context.addPath(
            CGPath(
                roundedRect: geometry.bubbleRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        )
        context.fillPath()
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: geometry.dotRect)

        let attributedText = ScreenshotTextLayout.attributedString(
            text: text,
            fontSize: fontSize,
            color: CGColor(gray: 1, alpha: 1)
        )
        let originalLine = CTLineCreateWithAttributedString(attributedText)
        let truncationToken = CTLineCreateWithAttributedString(
            ScreenshotTextLayout.attributedString(
                text: "…",
                fontSize: fontSize,
                color: CGColor(gray: 1, alpha: 1)
            )
        )
        let line = CTLineCreateTruncatedLine(
            originalLine,
            Double(geometry.textRect.width),
            .end,
            truncationToken
        ) ?? originalLine
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        context.textPosition = CGPoint(
            x: geometry.textRect.minX,
            y: geometry.textRect.midY - (ascent - descent) / 2
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// 判断 `isMosaic` 所描述的截图录屏核心领域条件是否成立。
    private static func isMosaic(_ annotation: ScreenshotAnnotation) -> Bool {
        if case .mosaic = annotation {
            return true
        }
        return false
    }
}
