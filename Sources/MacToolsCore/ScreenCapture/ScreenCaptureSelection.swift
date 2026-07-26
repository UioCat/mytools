// `ScreenCaptureSelection` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import CoreGraphics

/// 封装 `ScreenCaptureSelection` 在截图录屏核心领域中的值语义和相关操作。
public struct ScreenCaptureSelection: Equatable, Sendable {
    public static let minimumSideLength: CGFloat = 8

    public let displayID: UInt32
    public let displayFrame: CGRect
    public let rawSelectionFrame: CGRect

    /// 创建 `ScreenCaptureSelection`，保存传入依赖并建立初始状态。
    public init(displayID: UInt32, displayFrame: CGRect, rawSelectionFrame: CGRect) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.rawSelectionFrame = rawSelectionFrame
    }

    public var frame: CGRect {
        rawSelectionFrame.standardized.intersection(displayFrame).integral
    }

    public var isValid: Bool {
        frame.width >= Self.minimumSideLength && frame.height >= Self.minimumSideLength
    }

    public var displayRelativeFrame: CGRect {
        frame.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    public var screenCaptureKitSourceFrame: CGRect {
        let appKitFrame = displayRelativeFrame
        return CGRect(
            x: appKitFrame.minX,
            y: displayFrame.height - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}
