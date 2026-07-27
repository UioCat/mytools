// `AppSettings` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import Foundation

/// 封装 `HotKeyBinding` 在设置与凭据领域中的值语义和相关操作。
public struct HotKeyBinding: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: [String]

    /// 创建 `HotKeyBinding`，保存传入依赖并建立初始状态。
    public init(key: String, modifiers: [String]) {
        self.key = Self.normalizedKey(key)
        self.modifiers = Self.normalizedModifiers(modifiers)
    }

    public var displayValue: String {
        (modifiers + [key]).joined(separator: "+")
    }

    public var isUsableGlobalShortcut: Bool {
        !key.isEmpty && !modifiers.isEmpty
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case key
        case modifiers
    }

    /// 创建 `HotKeyBinding`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try container.decodeIfPresent(String.self, forKey: .key) ?? "",
            modifiers: try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        )
    }

    /// 转换 `encode` 接收的设置与凭据领域数据，并返回规范化结果。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers, forKey: .modifiers)
    }

    /// 转换 `normalizedModifiers` 接收的设置与凭据领域数据，并返回规范化结果。
    private static func normalizedModifiers(_ modifiers: [String]) -> [String] {
        let canonicalModifiers = modifiers.compactMap(canonicalModifier(_:))
        var seen = Set<String>()
        return modifierDisplayOrder.filter { modifier in
            canonicalModifiers.contains(modifier) && seen.insert(modifier).inserted
        }
    }

    /// 判断 `canonicalModifier` 所描述的设置与凭据领域条件是否成立。
    private static func canonicalModifier(_ modifier: String) -> String? {
        let normalized = modifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "control", "ctrl", "⌃":
            return "Control"
        case "option", "alt", "opt", "⌥":
            return "Option"
        case "shift", "⇧":
            return "Shift"
        case "command", "cmd", "⌘":
            return "Command"
        default:
            return nil
        }
    }

    /// 转换 `normalizedKey` 接收的设置与凭据领域数据，并返回规范化结果。
    private static func normalizedKey(_ key: String) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsedKey = trimmedKey.replacingOccurrences(of: " ", with: "").lowercased()

        switch collapsedKey {
        case "space", "spacebar", "空格":
            return "Space"
        case "left", "leftarrow", "arrowleft", "←":
            return "Left"
        case "right", "rightarrow", "arrowright", "→":
            return "Right"
        case "up", "uparrow", "arrowup", "↑":
            return "Up"
        case "down", "downarrow", "arrowdown", "↓":
            return "Down"
        case "return", "enter", "回车":
            return "Return"
        case "esc", "escape":
            return "Escape"
        case "del", "delete", "backspace":
            return "Delete"
        default:
            break
        }

        if trimmedKey.count == 1 {
            return trimmedKey.uppercased()
        }

        let uppercasedKey = trimmedKey.uppercased()
        if uppercasedKey.range(of: #"^F([1-9]|1[0-9]|20)$"#, options: .regularExpression) != nil {
            return uppercasedKey
        }

        return trimmedKey
    }

    private static let modifierDisplayOrder = ["Control", "Option", "Shift", "Command"]
}

/// 封装 `ClipboardSettings` 在设置与凭据领域中的值语义和相关操作。
public struct ClipboardSettings: Codable, Equatable, Sendable {
    public static let fixedHistoryLimit = 500

    public var isRecordingEnabled: Bool
    public private(set) var maxHistoryCount: Int
    public var maxCacheMegabytes: Int
    public var cacheStoragePath: String

    /// 创建 `ClipboardSettings`，保存传入依赖并建立初始状态。
    public init(
        isRecordingEnabled: Bool,
        maxHistoryCount: Int,
        maxCacheMegabytes: Int,
        cacheStoragePath: String = ""
    ) {
        self.isRecordingEnabled = isRecordingEnabled
        self.maxHistoryCount = Self.fixedHistoryLimit
        self.maxCacheMegabytes = ClipboardCacheLimit.normalizedMegabytes(maxCacheMegabytes)
        self.cacheStoragePath = cacheStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 计算并返回 `cacheDirectory` 对应的设置与凭据领域数据或状态结果。
    public func cacheDirectory(defaultDirectory: URL) -> URL {
        ClipboardCacheStorageDisplay.directoryURL(
            configuredPath: cacheStoragePath,
            defaultDirectory: defaultDirectory
        )
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case isRecordingEnabled
        case maxHistoryCount
        case maxCacheMegabytes
        case cacheStoragePath
    }

    /// 创建 `ClipboardSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isRecordingEnabled: try container.decodeIfPresent(Bool.self, forKey: .isRecordingEnabled) ?? true,
            maxHistoryCount: Self.fixedHistoryLimit,
            maxCacheMegabytes: try container.decodeIfPresent(Int.self, forKey: .maxCacheMegabytes)
                ?? ClipboardCacheLimit.defaultMegabytes,
            cacheStoragePath: try container.decodeIfPresent(String.self, forKey: .cacheStoragePath) ?? ""
        )
    }

    /// 转换 `encode` 接收的设置与凭据领域数据，并返回规范化结果。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isRecordingEnabled, forKey: .isRecordingEnabled)
        try container.encode(Self.fixedHistoryLimit, forKey: .maxHistoryCount)
        try container.encode(maxCacheMegabytes, forKey: .maxCacheMegabytes)
        try container.encode(cacheStoragePath, forKey: .cacheStoragePath)
    }
}

/// 描述 `ClipboardCacheStorageDisplay` 在设置与凭据领域中可取的状态、选项或错误。
public enum ClipboardCacheStorageDisplay {
    public static var defaultDirectory: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("MacTools", isDirectory: true)
            .appendingPathComponent("ClipboardCache", isDirectory: true)
    }

    /// 计算并返回 `displayPath` 对应的设置与凭据领域数据或状态结果。
    public static func displayPath(configuredPath: String, defaultDirectory: URL) -> String {
        NSString(
            string: directoryURL(
                configuredPath: configuredPath,
                defaultDirectory: defaultDirectory
            ).path
        ).abbreviatingWithTildeInPath
    }

    /// 计算并返回 `directoryURL` 对应的设置与凭据领域数据或状态结果。
    static func directoryURL(configuredPath: String, defaultDirectory: URL) -> URL {
        let trimmedPath = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return defaultDirectory
        }

        return URL(
            fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath,
            isDirectory: true
        )
    }
}

/// 描述 `ClipboardCacheLimit` 在设置与凭据领域中可取的状态、选项或错误。
public enum ClipboardCacheLimit {
    public static let allowedMegabytes = [200, 500, 1024, 2048]
    public static let defaultMegabytes = 1024

    /// 转换 `normalizedMegabytes` 接收的设置与凭据领域数据，并返回规范化结果。
    public static func normalizedMegabytes(_ megabytes: Int) -> Int {
        allowedMegabytes.min { lhs, rhs in
            let lhsDistance = abs(lhs - megabytes)
            let rhsDistance = abs(rhs - megabytes)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        } ?? defaultMegabytes
    }

    /// 计算并返回 `bytes` 对应的设置与凭据领域数据或状态结果。
    public static func bytes(forMegabytes megabytes: Int) -> Int {
        normalizedMegabytes(megabytes) * 1024 * 1024
    }

    /// 计算并返回 `displayValue` 对应的设置与凭据领域数据或状态结果。
    public static func displayValue(for megabytes: Int) -> String {
        "\(normalizedMegabytes(megabytes)) MB"
    }
}

/// 封装 `SuperRightClickSettings` 在设置与凭据领域中的值语义和相关操作。
public struct SuperRightClickSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var longPressMilliseconds: Int

    /// 创建 `SuperRightClickSettings`，保存传入依赖并建立初始状态。
    public init(isEnabled: Bool, longPressMilliseconds: Int) {
        self.isEnabled = isEnabled
        self.longPressMilliseconds = SuperRightClickResponseSpeed.normalizedMilliseconds(longPressMilliseconds)
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case longPressMilliseconds
    }

    /// 创建 `SuperRightClickSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.longPressMilliseconds = SuperRightClickResponseSpeed.normalizedMilliseconds(
            try container.decodeIfPresent(Int.self, forKey: .longPressMilliseconds)
                ?? SuperRightClickResponseSpeed.minimumMilliseconds
        )
    }

    /// 转换 `encode` 接收的设置与凭据领域数据，并返回规范化结果。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(longPressMilliseconds, forKey: .longPressMilliseconds)
    }
}

/// 描述 `SuperRightClickResponseSpeed` 在设置与凭据领域中可取的状态、选项或错误。
public enum SuperRightClickResponseSpeed {
    public static let minimumMilliseconds = 250
    public static let maximumMilliseconds = 350
    public static let stepMilliseconds = 50
    public static let markerMilliseconds = [250, 300, 350]

    /// 转换 `normalizedMilliseconds` 接收的设置与凭据领域数据，并返回规范化结果。
    public static func normalizedMilliseconds(_ milliseconds: Int) -> Int {
        let clampedMilliseconds = min(
            max(milliseconds, minimumMilliseconds),
            maximumMilliseconds
        )
        let offset = clampedMilliseconds - minimumMilliseconds
        let roundedStepCount = Int(
            (Double(offset) / Double(stepMilliseconds)).rounded()
        )
        return minimumMilliseconds + roundedStepCount * stepMilliseconds
    }

    /// 计算并返回 `clampedSliderValue` 对应的设置与凭据领域数据或状态结果。
    public static func clampedSliderValue(_ milliseconds: Double) -> Double {
        min(
            max(milliseconds, Double(minimumMilliseconds)),
            Double(maximumMilliseconds)
        )
    }

    /// 提交 `committedMilliseconds` 对应的设置与凭据领域状态，并记录后续流程所需的进度。
    public static func committedMilliseconds(forSliderValue milliseconds: Double) -> Int {
        normalizedMilliseconds(Int(clampedSliderValue(milliseconds).rounded()))
    }

    /// 计算并返回 `displayValue` 对应的设置与凭据领域数据或状态结果。
    public static func displayValue(for milliseconds: Int) -> String {
        "\(normalizedMilliseconds(milliseconds)) 毫秒"
    }
}

/// 封装 `TranslationSettings` 在设置与凭据领域中的值语义和相关操作。
public struct TranslationSettings: Codable, Equatable, Sendable {
    public static let defaultProviderID = "bailian"
    public static let defaultModel = "qwen-mt-turbo"
    public static let defaultEndpointURLString = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"

    public var providerID: String
    public var apiKey: String
    public var model: String
    public var endpointURLString: String

    /// 创建 `TranslationSettings`，保存传入依赖并建立初始状态。
    public init(
        providerID: String = Self.defaultProviderID,
        apiKey: String = "",
        model: String = Self.defaultModel,
        endpointURLString: String = Self.defaultEndpointURLString
    ) {
        self.providerID = providerID
        self.apiKey = apiKey
        self.model = model
        self.endpointURLString = endpointURLString
    }

    public var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 计算并返回 `resolvingAPIKey` 对应的设置与凭据领域数据或状态结果。
    public func resolvingAPIKey(currentAPIKey: String, wasEdited: Bool) -> Self {
        guard !wasEdited else { return self }
        var resolved = self
        resolved.apiKey = currentAPIKey
        return resolved
    }

    public var bailianConfiguration: BailianTranslationConfiguration? {
        guard isConfigured, let endpointURL = URL(string: endpointURLString) else {
            return nil
        }

        return BailianTranslationConfiguration(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            endpointURL: endpointURL
        )
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case providerID
        case apiKey
        case model
        case endpointURLString
    }

    /// 创建 `TranslationSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerID = try container.decodeIfPresent(String.self, forKey: .providerID) ?? Self.defaultProviderID
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        self.endpointURLString = try container.decodeIfPresent(String.self, forKey: .endpointURLString) ?? Self.defaultEndpointURLString
    }

    /// 转换 `encode` 接收的设置与凭据领域数据，并返回规范化结果。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(model, forKey: .model)
        try container.encode(endpointURLString, forKey: .endpointURLString)
    }
}

/// 封装 `ScreenCaptureSettings` 在设置与凭据领域中的值语义和相关操作。
public struct ScreenCaptureSettings: Codable, Equatable, Sendable {
    public var annotationTool: ScreenshotAnnotationTool
    public var annotationColor: ScreenshotAnnotationColor
    public var annotationLineWidth: ScreenshotAnnotationLineWidth

    public static let defaults = ScreenCaptureSettings(
        annotationTool: .line,
        annotationColor: .blue,
        annotationLineWidth: .medium
    )

    /// 创建 `ScreenCaptureSettings`，保存传入依赖并建立初始状态。
    public init(
        annotationTool: ScreenshotAnnotationTool = .line,
        annotationColor: ScreenshotAnnotationColor = .blue,
        annotationLineWidth: ScreenshotAnnotationLineWidth = .medium
    ) {
        self.annotationTool = annotationTool
        self.annotationColor = annotationColor.nearestPreset
        self.annotationLineWidth = annotationLineWidth
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case annotationTool
        case annotationColor
        case annotationLineWidth
    }

    /// 创建 `ScreenCaptureSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.annotationTool = (try? container.decodeIfPresent(
            ScreenshotAnnotationTool.self,
            forKey: .annotationTool
        )) ?? Self.defaults.annotationTool
        let decodedColor = (try? container.decodeIfPresent(
            ScreenshotAnnotationColor.self,
            forKey: .annotationColor
        )) ?? Self.defaults.annotationColor
        self.annotationColor = decodedColor.nearestPreset
        self.annotationLineWidth = (try? container.decodeIfPresent(
            ScreenshotAnnotationLineWidth.self,
            forKey: .annotationLineWidth
        )) ?? Self.defaults.annotationLineWidth
    }
}

/// 描述 `AppAppearanceMode` 在设置与凭据领域中可取的状态、选项或错误。
public enum AppAppearanceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case followSystem
    case light
    case dark

    public var displayName: String {
        switch self {
        case .followSystem:
            return "跟随系统"
        case .light:
            return "浅色模式"
        case .dark:
            return "深色模式"
        }
    }
}

/// 描述 `ClipboardSyncScope` 在设置与凭据领域中可取的状态、选项或错误。
public enum ClipboardSyncScope: String, Codable, CaseIterable, Equatable, Sendable {
    case favoritesAndPinned
    case allHistory

    public var displayName: String {
        switch self {
        case .favoritesAndPinned:
            return "仅收藏与置顶"
        case .allHistory:
            return "全部历史"
        }
    }
}

/// 封装 `SyncSettings` 在设置与凭据领域中的值语义和相关操作。
public struct SyncSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var clipboardScope: ClipboardSyncScope
    public var storageLimit: SyncStorageLimit

    public static let defaults = SyncSettings(
        isEnabled: false,
        clipboardScope: .favoritesAndPinned,
        storageLimit: .default
    )

    /// 创建 `SyncSettings`，保存传入依赖并建立初始状态。
    public init(
        isEnabled: Bool,
        clipboardScope: ClipboardSyncScope,
        storageLimit: SyncStorageLimit = .default
    ) {
        self.isEnabled = isEnabled
        self.clipboardScope = clipboardScope
        self.storageLimit = storageLimit
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case clipboardScope
        case storageLimit
    }

    /// 创建 `SyncSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        self.clipboardScope = try container.decodeIfPresent(
            ClipboardSyncScope.self,
            forKey: .clipboardScope
        ) ?? .favoritesAndPinned
        self.storageLimit = try container.decodeIfPresent(
            SyncStorageLimit.self,
            forKey: .storageLimit
        ) ?? .default
    }
}

/// 封装 `SyncStorageUsage` 在设置与凭据领域中的值语义和相关操作。
public struct SyncStorageUsage: Equatable, Sendable {
    public var usedBytes: Int64
    public var capacityBytes: Int64
    public var ordinaryHistoryCount: Int
    public var imageBytes: Int64
    public var textBytes: Int64
    public var metadataBytes: Int64

    public static let empty = SyncStorageUsage(
        usedBytes: 0,
        capacityBytes: SyncStorageLimit.default.byteLimit,
        ordinaryHistoryCount: 0,
        imageBytes: 0,
        textBytes: 0,
        metadataBytes: 0
    )

    /// 创建 `SyncStorageUsage`，保存传入依赖并建立初始状态。
    public init(
        usedBytes: Int64,
        capacityBytes: Int64,
        ordinaryHistoryCount: Int,
        imageBytes: Int64,
        textBytes: Int64,
        metadataBytes: Int64
    ) {
        self.usedBytes = usedBytes
        self.capacityBytes = capacityBytes
        self.ordinaryHistoryCount = ordinaryHistoryCount
        self.imageBytes = imageBytes
        self.textBytes = textBytes
        self.metadataBytes = metadataBytes
    }
}

/// 描述 `SyncStatus` 在设置与凭据领域中可取的状态、选项或错误。
public enum SyncStatus: Equatable, Sendable {
    case unconfigured
    case off
    case preparingFolder
    case syncing
    case waitingForDownload
    case synced(lastSyncAt: Date?, usage: SyncStorageUsage)
    case capacityFull(usage: SyncStorageUsage)
    case folderUnavailable
    case protocolIncompatible
    case failed

    public var displayName: String {
        switch self {
        case .unconfigured: return "未选择同步文件夹"
        case .off: return "已关闭"
        case .preparingFolder: return "正在准备同步文件夹"
        case .syncing: return "正在同步"
        case .synced: return "已同步"
        case .waitingForDownload: return "等待 iCloud 下载"
        case .capacityFull: return "同步空间已满"
        case .folderUnavailable: return "同步文件夹不可用"
        case .protocolIncompatible: return "同步协议版本不兼容"
        case .failed: return "同步失败"
        }
    }

    public var storageUsage: SyncStorageUsage? {
        switch self {
        case let .synced(_, usage), let .capacityFull(usage): return usage
        default: return nil
        }
    }
}

/// 封装 `AppSettings` 在设置与凭据领域中的值语义和相关操作。
public struct AppSettings: Codable, Equatable, Sendable {
    public var mainPanelShortcut: HotKeyBinding
    public var clipboardShortcut: HotKeyBinding
    public var reservedTool2Shortcut: HotKeyBinding
    public var reservedTool3Shortcut: HotKeyBinding
    public var clipboard: ClipboardSettings
    public var superRightClick: SuperRightClickSettings
    public var translation: TranslationSettings
    public var windowLayout: WindowLayoutSettings
    public var screenCapture: ScreenCaptureSettings
    public var appearanceMode: AppAppearanceMode
    public var sync: SyncSettings

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
            longPressMilliseconds: SuperRightClickResponseSpeed.minimumMilliseconds
        ),
        translation: TranslationSettings(),
        windowLayout: .defaults,
        screenCapture: .defaults,
        appearanceMode: .followSystem,
        sync: .defaults
    )

    /// 创建 `AppSettings`，保存传入依赖并建立初始状态。
    public init(
        mainPanelShortcut: HotKeyBinding,
        clipboardShortcut: HotKeyBinding,
        reservedTool2Shortcut: HotKeyBinding,
        reservedTool3Shortcut: HotKeyBinding,
        clipboard: ClipboardSettings,
        superRightClick: SuperRightClickSettings,
        translation: TranslationSettings,
        windowLayout: WindowLayoutSettings,
        screenCapture: ScreenCaptureSettings = .defaults,
        appearanceMode: AppAppearanceMode = .followSystem,
        sync: SyncSettings = .defaults
    ) {
        self.mainPanelShortcut = mainPanelShortcut
        self.clipboardShortcut = clipboardShortcut
        self.reservedTool2Shortcut = reservedTool2Shortcut
        self.reservedTool3Shortcut = reservedTool3Shortcut
        self.clipboard = clipboard
        self.superRightClick = superRightClick
        self.translation = translation
        self.windowLayout = windowLayout
        self.screenCapture = screenCapture
        self.appearanceMode = appearanceMode
        self.sync = sync
    }

    /// 描述 `CodingKeys` 在设置与凭据领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case mainPanelShortcut
        case clipboardShortcut
        case reservedTool2Shortcut
        case reservedTool3Shortcut
        case clipboard
        case superRightClick
        case translation
        case windowLayout
        case screenCapture
        case appearanceMode
        case sync
    }

    /// 创建 `AppSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mainPanelShortcut = try container.decodeIfPresent(HotKeyBinding.self, forKey: .mainPanelShortcut)
            ?? Self.defaults.mainPanelShortcut
        self.clipboardShortcut = try container.decodeIfPresent(HotKeyBinding.self, forKey: .clipboardShortcut)
            ?? Self.defaults.clipboardShortcut
        self.reservedTool2Shortcut = try container.decodeIfPresent(HotKeyBinding.self, forKey: .reservedTool2Shortcut)
            ?? Self.defaults.reservedTool2Shortcut
        self.reservedTool3Shortcut = try container.decodeIfPresent(HotKeyBinding.self, forKey: .reservedTool3Shortcut)
            ?? Self.defaults.reservedTool3Shortcut
        self.clipboard = try container.decodeIfPresent(ClipboardSettings.self, forKey: .clipboard)
            ?? Self.defaults.clipboard
        self.superRightClick = try container.decodeIfPresent(SuperRightClickSettings.self, forKey: .superRightClick)
            ?? Self.defaults.superRightClick
        self.translation = try container.decodeIfPresent(TranslationSettings.self, forKey: .translation)
            ?? Self.defaults.translation
        self.windowLayout = try container.decodeIfPresent(WindowLayoutSettings.self, forKey: .windowLayout)
            ?? Self.defaults.windowLayout
        self.screenCapture = try container.decodeIfPresent(ScreenCaptureSettings.self, forKey: .screenCapture)
            ?? Self.defaults.screenCapture
        self.appearanceMode = (try? container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode))
            ?? Self.defaults.appearanceMode
        self.sync = try container.decodeIfPresent(SyncSettings.self, forKey: .sync)
            ?? Self.defaults.sync
    }

    /// 转换 `encode` 接收的设置与凭据领域数据，并返回规范化结果。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mainPanelShortcut, forKey: .mainPanelShortcut)
        try container.encode(clipboardShortcut, forKey: .clipboardShortcut)
        try container.encode(reservedTool2Shortcut, forKey: .reservedTool2Shortcut)
        try container.encode(reservedTool3Shortcut, forKey: .reservedTool3Shortcut)
        try container.encode(clipboard, forKey: .clipboard)
        try container.encode(superRightClick, forKey: .superRightClick)
        try container.encode(translation, forKey: .translation)
        try container.encode(windowLayout, forKey: .windowLayout)
        try container.encode(screenCapture, forKey: .screenCapture)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(sync, forKey: .sync)
    }
}
