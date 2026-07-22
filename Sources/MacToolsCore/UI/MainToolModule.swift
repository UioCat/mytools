import Foundation

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

public enum PanelKeyCommand: Equatable, Sendable {
    case dismiss
}

public enum ToolModulePresentation: Sendable {
    case window
    case embedded
}

public struct PanelKeyCommandResolver {
    public init() {}

    public func command(forKeyCode keyCode: UInt16) -> PanelKeyCommand? {
        keyCode == 53 ? .dismiss : nil
    }
}
