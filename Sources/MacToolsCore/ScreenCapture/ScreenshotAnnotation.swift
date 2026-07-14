import CoreGraphics

public struct ScreenshotAnnotationColor: Codable, Equatable, Hashable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = ScreenshotAnnotationColor(red: 0.95, green: 0.2, blue: 0.18)
    public static let orange = ScreenshotAnnotationColor(red: 1, green: 0.55, blue: 0.1)
    public static let yellow = ScreenshotAnnotationColor(red: 1, green: 0.82, blue: 0.12)
    public static let green = ScreenshotAnnotationColor(red: 0.18, green: 0.72, blue: 0.3)
    public static let blue = ScreenshotAnnotationColor(red: 0, green: 0.48, blue: 1)
    public static let purple = ScreenshotAnnotationColor(red: 0.58, green: 0.3, blue: 0.95)
    public static let black = ScreenshotAnnotationColor(red: 0.08, green: 0.08, blue: 0.1)
    public static let white = ScreenshotAnnotationColor(red: 1, green: 1, blue: 1)

    public static let presets: [ScreenshotAnnotationColor] = [
        .red, .orange, .yellow, .green, .blue, .purple, .black, .white
    ]

    public var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public enum ScreenshotAnnotationLineWidth: String, CaseIterable, Codable, Equatable {
    case thin
    case medium
    case thick

    public var points: CGFloat {
        switch self {
        case .thin:
            return 2
        case .medium:
            return 3
        case .thick:
            return 6
        }
    }
}

public enum ScreenshotMosaicOutlinePolicy {
    public static func shouldShowOutline(isPreview: Bool) -> Bool {
        isPreview
    }
}

public enum ScreenshotAnnotationArrowStyle {
    private static let headLengthToLineWidthRatio: CGFloat = 10.0 / 3.0

    public static func headLength(forLineWidth lineWidth: CGFloat) -> CGFloat {
        lineWidth * headLengthToLineWidthRatio
    }
}

public enum ScreenshotAnnotation: Equatable {
    case line(
        start: CGPoint,
        end: CGPoint,
        color: ScreenshotAnnotationColor = .blue,
        lineWidth: CGFloat = ScreenshotAnnotationLineWidth.medium.points
    )
    case arrow(
        start: CGPoint,
        end: CGPoint,
        color: ScreenshotAnnotationColor = .blue,
        lineWidth: CGFloat = ScreenshotAnnotationLineWidth.medium.points
    )
    case rectangle(
        CGRect,
        color: ScreenshotAnnotationColor = .blue,
        lineWidth: CGFloat = ScreenshotAnnotationLineWidth.medium.points
    )
    case circle(
        CGRect,
        color: ScreenshotAnnotationColor = .blue,
        lineWidth: CGFloat = ScreenshotAnnotationLineWidth.medium.points
    )
    case mosaic(CGRect)

    public static func circle(
        from start: CGPoint,
        to end: CGPoint,
        color: ScreenshotAnnotationColor = .blue,
        lineWidth: CGFloat = ScreenshotAnnotationLineWidth.medium.points
    ) -> ScreenshotAnnotation {
        let side = min(abs(end.x - start.x), abs(end.y - start.y))
        let rect = CGRect(
            x: end.x >= start.x ? start.x : start.x - side,
            y: end.y >= start.y ? start.y : start.y - side,
            width: side,
            height: side
        )
        return .circle(rect, color: color, lineWidth: lineWidth)
    }
}

public struct ScreenshotAnnotationStore: Equatable {
    public private(set) var annotations: [ScreenshotAnnotation] = []

    public init() {}

    public mutating func append(_ annotation: ScreenshotAnnotation) {
        annotations.append(annotation)
    }

    @discardableResult
    public mutating func undo() -> ScreenshotAnnotation? {
        annotations.popLast()
    }
}
