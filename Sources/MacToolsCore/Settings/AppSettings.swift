import Foundation

public struct HotKeyBinding: Codable, Equatable {
    public var key: String
    public var modifiers: [String]

    public var displayValue: String {
        (modifiers + [key]).joined(separator: "+")
    }
}

public struct ClipboardSettings: Codable, Equatable {
    public var isRecordingEnabled: Bool
    public var maxHistoryCount: Int
    public var maxCacheMegabytes: Int
}

public struct SuperRightClickSettings: Codable, Equatable {
    public var isEnabled: Bool
    public var longPressMilliseconds: Int
}

public struct TranslationSettings: Codable, Equatable {
    public var providerID: String
}

public struct AppSettings: Codable, Equatable {
    public var mainPanelShortcut: HotKeyBinding
    public var clipboardShortcut: HotKeyBinding
    public var reservedTool2Shortcut: HotKeyBinding
    public var reservedTool3Shortcut: HotKeyBinding
    public var clipboard: ClipboardSettings
    public var superRightClick: SuperRightClickSettings
    public var translation: TranslationSettings

    public static let defaults = AppSettings(
        mainPanelShortcut: HotKeyBinding(key: "Space", modifiers: ["Option"]),
        clipboardShortcut: HotKeyBinding(key: "1", modifiers: ["Option"]),
        reservedTool2Shortcut: HotKeyBinding(key: "2", modifiers: ["Option"]),
        reservedTool3Shortcut: HotKeyBinding(key: "3", modifiers: ["Option"]),
        clipboard: ClipboardSettings(
            isRecordingEnabled: true,
            maxHistoryCount: 500,
            maxCacheMegabytes: 1024
        ),
        superRightClick: SuperRightClickSettings(
            isEnabled: true,
            longPressMilliseconds: 600
        ),
        translation: TranslationSettings(providerID: "baidu")
    )
}
