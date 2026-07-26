// `ScreenshotAnnotation` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import CoreGraphics

/// 描述 `ScreenshotAnnotationTool` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenshotAnnotationTool: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case line
    case freehand
    case arrow
    case rectangle
    case mosaic
}

/// 封装 `ScreenshotAnnotationColor` 在截图录屏核心领域中的值语义和相关操作。
public struct ScreenshotAnnotationColor: Codable, Equatable, Hashable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    /// 创建 `ScreenshotAnnotationColor`，保存传入依赖并建立初始状态。
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

    public var nearestPreset: ScreenshotAnnotationColor {
        Self.presets.min {
            squaredDistance(to: $0) < squaredDistance(to: $1)
        } ?? .blue
    }

    /// 计算并返回 `squaredDistance` 对应的截图录屏核心领域数据或状态结果。
    private func squaredDistance(to other: ScreenshotAnnotationColor) -> CGFloat {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        let alphaDelta = alpha - other.alpha
        return redDelta * redDelta
            + greenDelta * greenDelta
            + blueDelta * blueDelta
            + alphaDelta * alphaDelta
    }
}

/// 描述 `ScreenshotAnnotationLineWidth` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenshotAnnotationLineWidth: String, CaseIterable, Codable, Equatable, Sendable {
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

/// 描述 `ScreenshotMosaicOutlinePolicy` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenshotMosaicOutlinePolicy {
    /// 判断 `shouldShowOutline` 所描述的截图录屏核心领域条件是否成立。
    public static func shouldShowOutline(isPreview: Bool) -> Bool {
        isPreview
    }
}

/// 描述 `ScreenshotAnnotationArrowStyle` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenshotAnnotationArrowStyle {
    private static let headLengthToLineWidthRatio: CGFloat = 10.0 / 3.0

    /// 计算并返回 `headLength` 对应的截图录屏核心领域数据或状态结果。
    public static func headLength(forLineWidth lineWidth: CGFloat) -> CGFloat {
        lineWidth * headLengthToLineWidthRatio
    }
}

/// 描述 `ScreenshotAnnotation` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenshotAnnotation: Equatable, Sendable {
    case line(
        start: CGPoint,
        end: CGPoint,
        color: ScreenshotAnnotationColor = .blue,
        lineWidth: CGFloat = ScreenshotAnnotationLineWidth.medium.points
    )
    case freehand(
        points: [CGPoint],
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
    case mosaic(CGRect)
}

/// 封装 `ScreenshotFreehandStroke` 在截图录屏核心领域中的值语义和相关操作。
public struct ScreenshotFreehandStroke: Equatable, Sendable {
    public private(set) var points: [CGPoint] = []
    private var pathLength: CGFloat = 0

    /// 创建 `ScreenshotFreehandStroke`，保存传入依赖并建立初始状态。
    public init() {}

    /// 汇总或整理 `append` 涉及的截图录屏核心领域数据，并维护容量与保留规则。
    public mutating func append(_ point: CGPoint, minimumSampleDistance: CGFloat = 0.75) {
        guard let lastPoint = points.last else {
            points = [point]
            return
        }

        let segmentLength = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
        guard segmentLength >= max(0, minimumSampleDistance) else {
            return
        }
        points.append(point)
        pathLength += segmentLength
    }

    /// 计算并返回 `annotation` 对应的截图录屏核心领域数据或状态结果。
    public func annotation(
        color: ScreenshotAnnotationColor,
        lineWidth: CGFloat,
        minimumPathLength: CGFloat = 2
    ) -> ScreenshotAnnotation? {
        guard pathLength >= max(0, minimumPathLength), points.count >= 2 else {
            return nil
        }
        return .freehand(points: points, color: color, lineWidth: lineWidth)
    }
}

/// 封装 `ScreenshotAnnotationStore` 在截图录屏核心领域中的值语义和相关操作。
public struct ScreenshotAnnotationStore: Equatable, Sendable {
    public private(set) var annotations: [ScreenshotAnnotation] = []

    /// 创建 `ScreenshotAnnotationStore`，保存传入依赖并建立初始状态。
    public init() {}

    /// 汇总或整理 `append` 涉及的截图录屏核心领域数据，并维护容量与保留规则。
    public mutating func append(_ annotation: ScreenshotAnnotation) {
        annotations.append(annotation)
    }

    /// 计算并返回 `undo` 对应的截图录屏核心领域数据或状态结果。
    @discardableResult
    public mutating func undo() -> ScreenshotAnnotation? {
        annotations.popLast()
    }
}
