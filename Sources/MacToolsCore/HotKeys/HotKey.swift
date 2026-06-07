import Foundation

public enum HotKeyTarget: Equatable {
    case mainPanel
    case clipboard
    case translation
    case reservedTool3
    case windowLayout(WindowLayoutMode)

    public var rawValue: String {
        switch self {
        case .mainPanel:
            return "mainPanel"
        case .clipboard:
            return "clipboard"
        case .translation:
            return "translation"
        case .reservedTool3:
            return "reservedTool3"
        case .windowLayout(let mode):
            return "windowLayout.\(mode.rawValue)"
        }
    }
}

public struct HotKey: Equatable, Hashable {
    public let displayValue: String
    public let key: String
    public let modifiers: [String]

    public init(displayValue: String, key: String, modifiers: [String]) {
        self.displayValue = displayValue
        self.key = key
        self.modifiers = modifiers
    }
}

public protocol HotKeyRegistrar {
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws
    func unregisterAll()
}
