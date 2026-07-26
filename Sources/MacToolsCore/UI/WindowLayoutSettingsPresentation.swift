// `WindowLayoutSettingsPresentation` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import CoreGraphics

/// 描述 `SettingsPageColumnArrangement` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum SettingsPageColumnArrangement: Equatable {
    case twoColumns
    case stacked
}

/// 描述 `SettingsPageLayout` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum SettingsPageLayout {
    static let primaryColumnMinimumWidth: CGFloat = 320
    static let secondaryColumnMinimumWidth: CGFloat = 360
    static let columnSpacing: CGFloat = 14
    static let minimumTwoColumnContentWidth = primaryColumnMinimumWidth + secondaryColumnMinimumWidth + columnSpacing

    /// 构建并返回 `columnArrangement` 对应的 SwiftUI 界面内容或展示状态。
    static func columnArrangement(for availableWidth: CGFloat) -> SettingsPageColumnArrangement {
        availableWidth >= minimumTwoColumnContentWidth ? .twoColumns : .stacked
    }
}

/// 描述 `WindowLayoutPreviewGeometry` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum WindowLayoutPreviewGeometry {
    /// 构建并返回 `screenFrame` 对应的 SwiftUI 界面内容或展示状态。
    static func screenFrame(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: 1, dy: 1)
    }

    /// 构建并返回 `targetFrame` 对应的 SwiftUI 界面内容或展示状态。
    static func targetFrame(for segment: WindowLayoutPreviewSegment, in bounds: CGRect) -> CGRect {
        let placementArea = screenFrame(in: bounds).insetBy(dx: 2, dy: 2)

        return CGRect(
            x: placementArea.minX + placementArea.width * segment.x,
            y: placementArea.minY + placementArea.height * segment.y,
            width: placementArea.width * segment.width,
            height: placementArea.height * segment.height
        )
    }
}
