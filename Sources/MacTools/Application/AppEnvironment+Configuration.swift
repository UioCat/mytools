// 应用运行时的配置选择与保存前校验。
import Foundation
import MacToolsCore

/// 描述 `AppEnvironmentError` 在应用运行时与 AppKit 集成中可取的状态、选项或错误。
enum AppEnvironmentError: Error {
    case unavailable
    case syncFolderUnavailable
}

extension AppEnvironment {
    /// 在持久化前验证运行时快捷键，保存失败时恢复原注册。
    static func persistSettings(
        _ updated: AppSettings,
        restoring previous: AppSettings,
        validateHotKeys: (AppSettings) throws -> Void,
        persist: (AppSettings) throws -> Void
    ) throws {
        try validateHotKeys(updated)
        do {
            try persist(updated)
        } catch {
            try? validateHotKeys(previous)
            throw error
        }
    }

    /// 解析并返回 `resolveSyncFolderBookmark` 对应的应用运行时与 AppKit 集成结果。
    static func resolveSyncFolderBookmark(_ bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else {
            return nil
        }
        return url
    }

    /// 返回 MacTools 应用支持目录；系统目录不可用时使用临时目录作为隔离降级。
    static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("MacTools", isDirectory: true)
    }
}

/// 将受控 UI 验证数据与正常应用支持目录隔离。
struct AppEnvironmentStoreConfiguration {
    var supportDirectory: URL
    var isUIVerification: Bool

    static func make(
        defaultDirectory: URL,
        arguments: [String],
        environment: [String: String]
    ) -> Self {
        let verificationArguments = [
            "--ui-verification-open-settings",
            "--ui-verification-dark",
            "--ui-verification-check-for-updates"
        ]
        guard arguments.contains(where: verificationArguments.contains),
              let directory = environment["MACTOOLS_UI_VERIFICATION_DIRECTORY"],
              directory.hasPrefix("/") else {
            return Self(supportDirectory: defaultDirectory, isUIVerification: false)
        }
        return Self(supportDirectory: URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL, isUIVerification: true)
    }

    func initialSettings(_ settings: AppSettings) -> AppSettings {
        guard isUIVerification else { return settings }
        var settings = settings
        settings.clipboard.isRecordingEnabled = false
        settings.sync.isEnabled = false
        return settings
    }
}

/// 隔离验证只使用合成信封，空目录不得读取生产 Keychain。
struct UIVerificationLegacyCredentialReader: LegacyCredentialReading {
    func read(_ key: CredentialKey) throws -> String? { nil }
}
