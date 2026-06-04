import Foundation

public enum HotKeyTarget: String, Equatable {
    case mainPanel
    case clipboard
    case reservedTool2
    case reservedTool3
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
