// 超级右键文本预览的行数限制策略。
// 根据内容类型控制压缩范围，避免动作区被长文本挤出面板。

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
