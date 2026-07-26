// `ScreenCaptureResolutionPolicy` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import CoreGraphics

/// 描述 `ScreenCaptureResolutionPolicy` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenCaptureResolutionPolicy {
    /// 计算并返回 `outputPixelSize` 对应的截图录屏核心领域数据或状态结果。
    public static func outputPixelSize(
        for sourceSize: CGSize,
        pointPixelScale: CGFloat,
        purpose: ScreenCaptureMode
    ) -> CGSize {
        let outputScale: CGFloat = purpose == .screenshot ? max(1, pointPixelScale) : 1
        return CGSize(
            width: max(1, (sourceSize.width * outputScale).rounded()),
            height: max(1, (sourceSize.height * outputScale).rounded())
        )
    }
}
