// `MacToolsStorePaths` 的本地存储领域实现。
// 负责数据库、载荷文件和迁移事务，不管理运行时面板状态。

import Foundation

/// 封装 `MacToolsStorePaths` 在本地存储领域中的值语义和相关操作。
public struct MacToolsStorePaths: Equatable {
    public let supportDirectory: URL
    private let storeDirectoryOverride: URL?

    /// 创建 `MacToolsStorePaths`，保存传入依赖并建立初始状态。
    public init(supportDirectory: URL, storeDirectoryOverride: URL? = nil) {
        self.supportDirectory = supportDirectory
        self.storeDirectoryOverride = storeDirectoryOverride
    }

    public var storeDirectory: URL {
        storeDirectoryOverride
            ?? supportDirectory.appendingPathComponent("Store", isDirectory: true)
    }

    public var databaseURL: URL {
        storeDirectory.appendingPathComponent("mactools.sqlite3")
    }

    public var payloadsDirectory: URL {
        storeDirectory.appendingPathComponent("Payloads", isDirectory: true)
    }

    public var credentialsDirectory: URL {
        storeDirectory.appendingPathComponent("Credentials", isDirectory: true)
    }

    public var bailianCredentialURL: URL {
        credentialsDirectory.appendingPathComponent("bailian-api-key.v1.json")
    }

    public var credentialMigrationMarkerURL: URL {
        credentialsDirectory.appendingPathComponent("migration-v1.complete")
    }

    /// 运行 `runtimePayloadsDirectory` 对应的本地存储领域流程，直到完成或进入下一调度点。
    public func runtimePayloadsDirectory(
        persistentStoreAvailable: Bool,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        guard !persistentStoreAvailable else { return payloadsDirectory }
        return temporaryDirectory.appendingPathComponent(
            "MacTools-IsolatedFallback-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    public var legacyDatabaseURL: URL {
        supportDirectory.appendingPathComponent("Clipboard.sqlite")
    }

    public var legacyPayloadsDirectory: URL {
        supportDirectory.appendingPathComponent("ClipboardCache", isDirectory: true)
    }

    public var legacySettingsURL: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }
}
