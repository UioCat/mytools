// `HotKey` 的全局快捷键领域实现。
// 负责快捷键建模、注册和分发，不管理具体工具界面。

import Foundation

/// 描述 `HotKeyTarget` 在全局快捷键领域中可取的状态、选项或错误。
public enum HotKeyTarget: Equatable {
    case mainPanel
    case clipboard
    case translation
    case screenCapture
    case windowLayout(WindowLayoutMode)

    public var rawValue: String {
        switch self {
        case .mainPanel:
            return "mainPanel"
        case .clipboard:
            return "clipboard"
        case .translation:
            return "translation"
        case .screenCapture:
            return "screenCapture"
        case .windowLayout(let mode):
            return "windowLayout.\(mode.rawValue)"
        }
    }
}

/// 封装 `HotKey` 在全局快捷键领域中的值语义和相关操作。
public struct HotKey: Equatable, Hashable, Sendable {
    public let displayValue: String
    public let key: String
    public let modifiers: [String]

    /// 创建 `HotKey`，保存传入依赖并建立初始状态。
    public init(displayValue: String, key: String, modifiers: [String]) {
        self.displayValue = displayValue
        self.key = key
        self.modifiers = modifiers
    }
}

/// 定义 `HotKeyRegistrar` 在全局快捷键领域中需要满足的能力边界。
public protocol HotKeyRegistrar {
    /// 启动 `register` 对应的全局快捷键领域流程，并建立所需资源。
    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws
    /// 结束 `unregisterAll` 对应的全局快捷键领域流程，并释放或重置相关资源。
    func unregisterAll()
}

/// 捕获界面和 Carbon 注册器共用的受支持物理按键。
public enum HotKeyKeyCatalog {
    public static func keyCode(for key: String) -> UInt32? { keyCodes[key] }

    public static func keyName(for keyCode: UInt16) -> String? {
        keyCodes.first { $0.value == UInt32(keyCode) }?.key
    }

    private static let keyCodes: [String: UInt32] = [
        "A": 0,
        "S": 1,
        "D": 2,
        "F": 3,
        "H": 4,
        "G": 5,
        "Z": 6,
        "X": 7,
        "C": 8,
        "V": 9,
        "B": 11,
        "Q": 12,
        "W": 13,
        "E": 14,
        "R": 15,
        "Y": 16,
        "T": 17,
        "1": 18,
        "2": 19,
        "3": 20,
        "4": 21,
        "6": 22,
        "5": 23,
        "7": 26,
        "8": 28,
        "9": 25,
        "0": 29,
        "O": 31,
        "U": 32,
        "I": 34,
        "P": 35,
        "Return": 36,
        "L": 37,
        "J": 38,
        "K": 40,
        "N": 45,
        "M": 46,
        "Tab": 48,
        "Space": 49,
        "Delete": 51,
        "Escape": 53,
        "F5": 96,
        "F6": 97,
        "F7": 98,
        "F3": 99,
        "F8": 100,
        "F9": 101,
        "F11": 103,
        "F10": 109,
        "F12": 111,
        "F4": 118,
        "F2": 120,
        "F1": 122,
        "Left": 123,
        "Right": 124,
        "Down": 125,
        "Up": 126
    ]
}
