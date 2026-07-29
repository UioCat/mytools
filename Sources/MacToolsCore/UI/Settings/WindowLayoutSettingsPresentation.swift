// 窗口布局设置的预览几何和展示转换。
// 将领域布局映射为图标尺寸，不访问 Accessibility API。

import CoreGraphics

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
