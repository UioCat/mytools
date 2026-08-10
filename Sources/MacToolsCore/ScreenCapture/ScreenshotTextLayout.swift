// 截图文本与标签共用的排版几何，确保编辑预览和最终 PNG 使用同一套尺寸。

import AppKit
import CoreGraphics
import CoreText
import Foundation

public enum ScreenshotTextWeight: Equatable, Sendable {
    case regular
    case medium

    fileprivate var appKitWeight: NSFont.Weight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        }
    }
}

public struct ScreenshotTextLineMetrics: Equatable, Sendable {
    public let width: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public let leading: CGFloat
}

public struct ScreenshotLabelColorComponents: Equatable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public var relativeLuminance: CGFloat {
        0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
    }

    public func composited(over grayscale: CGFloat) -> ScreenshotLabelColorComponents {
        let background = min(max(grayscale, 0), 1)
        return ScreenshotLabelColorComponents(
            red: red * alpha + background * (1 - alpha),
            green: green * alpha + background * (1 - alpha),
            blue: blue * alpha + background * (1 - alpha),
            alpha: 1
        )
    }

    private func linearized(_ component: CGFloat) -> CGFloat {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

public enum ScreenshotLabelStyle {
    public static let backgroundColor = ScreenshotLabelColorComponents(
        red: 0.98,
        green: 0.98,
        blue: 0.97,
        alpha: 0.96
    )
    public static let foregroundColor = ScreenshotLabelColorComponents(
        red: 0.12,
        green: 0.13,
        blue: 0.15,
        alpha: 1
    )
    public static let borderColor = ScreenshotLabelColorComponents(
        red: 0.10,
        green: 0.12,
        blue: 0.15,
        alpha: 0.14
    )
    public static let shadowColor = ScreenshotLabelColorComponents(
        red: 0,
        green: 0,
        blue: 0,
        alpha: 0.18
    )

    public static func horizontalPadding(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.625
    }

    public static func verticalPadding(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.375
    }

    public static func labelGap(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.375
    }

    public static func dotDiameter(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.625
    }

    public static func glyphSafetyWidth(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.16
    }

    public static func borderWidth(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.0625
    }

    public static func shadowRadius(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.18
    }

    public static func shadowYOffset(for fontSize: CGFloat) -> CGFloat {
        max(1, fontSize) * 0.08
    }

    /// 标注模型和位图上下文均使用 y 轴向上的图像坐标，因此屏幕上向下的阴影需要负偏移。
    public static func imageShadowYOffset(for fontSize: CGFloat) -> CGFloat {
        -shadowYOffset(for: fontSize)
    }

    /// 描边与模糊阴影在气泡外侧的保守扩展量，用于宽度预算和边界约束。
    public static func visualOutset(for fontSize: CGFloat) -> CGFloat {
        max(
            borderWidth(for: fontSize) / 2,
            shadowRadius(for: fontSize) * 2 + abs(imageShadowYOffset(for: fontSize))
        )
    }

    public static func maximumBubbleWidth(
        in canvasWidth: CGFloat,
        fontSize: CGFloat,
        edgeInset: CGFloat
    ) -> CGFloat {
        max(
            1,
            canvasWidth
                - max(0, edgeInset) * 2
                - dotDiameter(for: fontSize)
                - labelGap(for: fontSize)
                - visualOutset(for: fontSize)
        )
    }

    public static func resolvedMaximumBubbleWidth(
        existingMaximumWidth: CGFloat,
        in canvasWidth: CGFloat,
        requestedFontSize: CGFloat?,
        edgeInset: CGFloat
    ) -> CGFloat {
        guard let requestedFontSize else {
            return existingMaximumWidth
        }
        return maximumBubbleWidth(
            in: canvasWidth,
            fontSize: requestedFontSize,
            edgeInset: edgeInset
        )
    }
}

public struct ScreenshotLabelGeometry: Equatable, Sendable {
    public let dotRect: CGRect
    public let bubbleRect: CGRect
    public let textRect: CGRect
    public let bounds: CGRect
    public let cornerRadius: CGFloat
    public let textBaselineY: CGFloat
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
        let horizontalPadding = ScreenshotLabelStyle.horizontalPadding(for: resolvedFontSize)
        let verticalPadding = ScreenshotLabelStyle.verticalPadding(for: resolvedFontSize)
        let labelGap = ScreenshotLabelStyle.labelGap(for: resolvedFontSize)
        let dotDiameter = ScreenshotLabelStyle.dotDiameter(for: resolvedFontSize)
        let availableTextWidth = max(
            minimumSingleLineTruncationWidth(fontSize: resolvedFontSize),
            maximumWidth - horizontalPadding * 2
        )
        let metrics = singleLineMetrics(text: text, fontSize: resolvedFontSize, weight: .medium)
        let measuredTextWidth = metrics.width
            + ScreenshotLabelStyle.glyphSafetyWidth(for: resolvedFontSize)
        let textWidth = min(availableTextWidth, ceil(measuredTextWidth))
        let bubbleWidth = textWidth + horizontalPadding * 2
        let lineHeight = resolvedFontSize * 1.25
        let bubbleHeight = lineHeight + verticalPadding * 2
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
        let borderBounds = bubbleRect.insetBy(
            dx: -ScreenshotLabelStyle.borderWidth(for: resolvedFontSize) / 2,
            dy: -ScreenshotLabelStyle.borderWidth(for: resolvedFontSize) / 2
        )
        let shadowBlurOutset = ScreenshotLabelStyle.shadowRadius(for: resolvedFontSize) * 2
        let shadowBounds = bubbleRect
            .insetBy(dx: -shadowBlurOutset, dy: -shadowBlurOutset)
            .offsetBy(
                dx: 0,
                dy: ScreenshotLabelStyle.imageShadowYOffset(for: resolvedFontSize)
            )
        return ScreenshotLabelGeometry(
            dotRect: dotRect,
            bubbleRect: bubbleRect,
            textRect: textRect,
            bounds: dotRect.union(borderBounds).union(shadowBounds),
            cornerRadius: resolvedFontSize * 0.5,
            textBaselineY: textRect.midY - (metrics.ascent - metrics.descent) / 2
        )
    }

    public static func singleLineWidth(text: String, fontSize: CGFloat) -> CGFloat {
        singleLineMetrics(text: text, fontSize: fontSize).width
    }

    public static func minimumSingleLineTruncationWidth(fontSize: CGFloat) -> CGFloat {
        ceil(singleLineMetrics(text: "…", fontSize: fontSize, weight: .medium).width)
    }

    public static func singleLineMetrics(
        text: String,
        fontSize: CGFloat,
        weight: ScreenshotTextWeight = .regular
    ) -> ScreenshotTextLineMetrics {
        let line = CTLineCreateWithAttributedString(
            attributedString(
                text: text.isEmpty ? " " : text,
                fontSize: fontSize,
                color: nil,
                weight: weight
            )
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return ScreenshotTextLineMetrics(
            width: width,
            ascent: ascent,
            descent: descent,
            leading: leading
        )
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
        color: CGColor?,
        weight: ScreenshotTextWeight = .regular
    ) -> CFAttributedString {
        let resolvedFontSize = max(1, fontSize)
        let font = NSFont.systemFont(ofSize: resolvedFontSize, weight: weight.appKitWeight) as CTFont
        var attributes: [CFString: Any] = [kCTFontAttributeName: font]
        if let color {
            attributes[kCTForegroundColorAttributeName] = color
        }
        return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
    }
}
