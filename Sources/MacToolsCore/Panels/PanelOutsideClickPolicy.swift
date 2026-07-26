// `PanelOutsideClickPolicy` 的面板领域实现。
// 负责窗口外观和交互策略，不持久化业务数据。

import CoreGraphics

/// 描述 `PanelOutsideClickPolicy` 在面板领域中可取的状态、选项或错误。
public enum PanelOutsideClickPolicy {
    /// 判断 `shouldDismiss` 所描述的面板领域条件是否成立。
    public static func shouldDismiss(
        panelFrame: CGRect,
        eventScreenLocation: CGPoint
    ) -> Bool {
        !panelFrame.contains(eventScreenLocation)
    }
}
