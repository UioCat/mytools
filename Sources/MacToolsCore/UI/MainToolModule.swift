// `MainToolModule` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import Foundation

/// 描述 `MainToolModule` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum MainToolModule: String, CaseIterable, Identifiable, Sendable {
    case settings
    case clipboard
    case translation

    public static let defaultModule: MainToolModule = .settings

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .settings:
            return "设置"
        case .clipboard:
            return "剪贴板"
        case .translation:
            return "翻译"
        }
    }

    public var subtitle: String {
        switch self {
        case .settings:
            return "快捷键、剪贴板、翻译和权限"
        case .clipboard:
            return "历史记录、搜索和快速粘贴"
        case .translation:
            return "百炼翻译与超级右键"
        }
    }

    public var iconName: String {
        switch self {
        case .settings:
            return "slider.horizontal.3"
        case .clipboard:
            return "doc.on.clipboard"
        case .translation:
            return "character.book.closed"
        }
    }
}

/// 描述 `PanelKeyCommand` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum PanelKeyCommand: Equatable, Sendable {
    case dismiss
}

/// 描述 `ToolModulePresentation` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum ToolModulePresentation: Sendable {
    case window
    case embedded
}

/// 封装 `PanelKeyCommandResolver` 在 SwiftUI 展示层中的值语义和相关操作。
public struct PanelKeyCommandResolver {
    /// 创建 `PanelKeyCommandResolver`，保存传入依赖并建立初始状态。
    public init() {}

    /// 构建并返回 `command` 对应的 SwiftUI 界面内容或展示状态。
    public func command(forKeyCode keyCode: UInt16) -> PanelKeyCommand? {
        keyCode == 53 ? .dismiss : nil
    }
}
