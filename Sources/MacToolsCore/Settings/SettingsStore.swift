// `SettingsStore` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import Foundation

/// 管理 `SettingsStore` 在设置与凭据领域中的生命周期、依赖和可变状态。
public final class SettingsStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// 创建 `SettingsStore`，保存传入依赖并建立初始状态。
    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// 读取并返回 `load` 对应的设置与凭据领域数据。
    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaults
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    /// 保存 `save` 接收的设置与凭据领域数据，并保持既有持久化约束。
    public func save(_ settings: AppSettings) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try SensitiveFilePermissions.prepareDirectory(at: directoryURL)

        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
        try SensitiveFilePermissions.secureFile(at: fileURL)
    }
}
