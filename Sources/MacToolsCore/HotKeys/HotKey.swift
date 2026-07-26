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
public struct HotKey: Equatable, Hashable {
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
