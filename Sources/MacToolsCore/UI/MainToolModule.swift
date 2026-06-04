import Foundation

public enum MainToolModule: String, CaseIterable, Identifiable {
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

public enum PanelKeyCommand: Equatable {
    case dismiss
}

public enum ToolModulePresentation {
    case window
    case embedded
}

public struct PanelKeyCommandResolver {
    public init() {}

    public func command(forKeyCode keyCode: UInt16) -> PanelKeyCommand? {
        keyCode == 53 ? .dismiss : nil
    }
}
