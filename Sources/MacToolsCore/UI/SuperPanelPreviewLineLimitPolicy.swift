// `SuperPanelPreviewLineLimitPolicy` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import Foundation

/// 描述 `SuperPanelPreviewLineLimitPolicy` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum SuperPanelPreviewLineLimitPolicy {
    /// 构建并返回 `lineLimit` 对应的 SwiftUI 界面内容或展示状态。
    public static func lineLimit(
        for kind: SuperPanelKind,
        row: SuperPanelPreviewRow
    ) -> Int? {
        switch kind {
        case .text, .textTransit:
            return nil
        case .fileSystem, .windowLayout:
            return 2
        }
    }
}
