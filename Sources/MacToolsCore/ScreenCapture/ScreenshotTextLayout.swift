// 截图文本与标签共用的排版几何，确保编辑预览和最终 PNG 使用同一套尺寸。

import CoreGraphics
import CoreText
import Foundation

public struct ScreenshotLabelGeometry: Equatable, Sendable {
    public let dotRect: CGRect
    public let bubbleRect: CGRect
    public let textRect: CGRect
    public let bounds: CGRect
    public let cornerRadius: CGFloat
}

public enum ScreenshotTextLayout {
    public static func labelGeometry(
        text: String,
        anchor: CGPoint,
        direction: ScreenshotLabelDirection,
        fontSize: CGFloat,
        maximumWidth: CGFloat
    ) -> ScreenshotLabelGeometry {
        let resolvedFontSize = max(1, fontSize)
        let horizontalPadding = resolvedFontSize * 0.5
        let verticalPadding = resolvedFontSize * 0.3125
        let labelGap = resolvedFontSize * 0.3125
        let dotDiameter = resolvedFontSize * 0.58
        let availableTextWidth = max(1, maximumWidth - horizontalPadding * 2)
        let measuredTextWidth = singleLineWidth(text: text, fontSize: resolvedFontSize)
        let textWidth = min(availableTextWidth, ceil(measuredTextWidth))
        let bubbleWidth = textWidth + horizontalPadding * 2
        let bubbleHeight = ceil(resolvedFontSize * 1.28) + verticalPadding * 2
        let bubbleOriginX: CGFloat
        switch direction {
        case .left:
            bubbleOriginX = anchor.x + dotDiameter / 2 + labelGap
        case .right:
            bubbleOriginX = anchor.x - dotDiameter / 2 - labelGap - bubbleWidth
        }
        let bubbleRect = CGRect(
            x: bubbleOriginX,
            y: anchor.y - bubbleHeight / 2,
            width: bubbleWidth,
            height: bubbleHeight
        )
        let dotRect = CGRect(
            x: anchor.x - dotDiameter / 2,
            y: anchor.y - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        let textRect = bubbleRect.insetBy(dx: horizontalPadding, dy: verticalPadding)
        return ScreenshotLabelGeometry(
            dotRect: dotRect,
            bubbleRect: bubbleRect,
            textRect: textRect,
            bounds: dotRect.union(bubbleRect),
            cornerRadius: resolvedFontSize * 0.5
        )
    }

    public static func singleLineWidth(text: String, fontSize: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            attributedString(text: text.isEmpty ? " " : text, fontSize: fontSize, color: nil)
        )
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    public static func multilineSize(
        text: String,
        fontSize: CGFloat,
        maximumWidth: CGFloat
    ) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributedString(text: text.isEmpty ? " " : text, fontSize: fontSize, color: nil)
        )
        return CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(),
            nil,
            CGSize(width: max(1, maximumWidth), height: .greatestFiniteMagnitude),
            nil
        )
    }

    static func attributedString(
        text: String,
        fontSize: CGFloat,
        color: CGColor?
    ) -> CFAttributedString {
        let font = CTFontCreateUIFontForLanguage(.system, max(1, fontSize), nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, max(1, fontSize), nil)
        var attributes: [CFString: Any] = [kCTFontAttributeName: font]
        if let color {
            attributes[kCTForegroundColorAttributeName] = color
        }
        return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    }
}
