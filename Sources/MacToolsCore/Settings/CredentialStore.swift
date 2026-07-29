// `CredentialStore` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import Foundation

/// 描述 `CredentialKey` 在设置与凭据领域中可取的状态、选项或错误。
public enum CredentialKey: String, Codable, Equatable, Sendable {
    case bailianAPIKey = "bailian.apiKey"
}

/// 定义 `LegacyCredentialReading` 在设置与凭据领域中需要满足的能力边界。
public protocol LegacyCredentialReading: Sendable {
    /// 读取并返回 `read` 对应的设置与凭据领域数据。
    func read(_ key: CredentialKey) throws -> String?
}

/// 描述 `CredentialAccessError` 在设置与凭据领域中可取的状态、选项或错误。
public enum CredentialAccessError: Error, Equatable, Sendable {
    case migrationVerificationFailed
}

/// 描述凭据加载结果对运行时发布状态和依赖服务的最小更新范围。
public struct CredentialRuntimeUpdateDecision: Equatable, Sendable {
    public let shouldUpdatePublishedValue: Bool
    public let shouldClearUnavailableState: Bool
    public let shouldRefreshDependentServices: Bool
}

/// 根据内存中的凭据状态决定是否需要发布界面状态或重建依赖服务。
public enum CredentialRuntimeUpdatePolicy {
    /// 相同凭据只恢复可用状态；仅凭据值变化时刷新翻译和全局右键依赖。
    public static func decision(
        settingsValue: String,
        publishedValue: String,
        isUnavailable: Bool,
        loadedValue: String
    ) -> CredentialRuntimeUpdateDecision {
        CredentialRuntimeUpdateDecision(
            shouldUpdatePublishedValue: publishedValue != loadedValue,
            shouldClearUnavailableState: isUnavailable,
            shouldRefreshDependentServices: settingsValue != loadedValue
        )
    }
}

/// 串行管理 `CredentialAccessCoordinator` 在设置与凭据领域中的可变状态和异步操作。
public actor CredentialAccessCoordinator {
    /// 封装 `LoadResult` 在设置与凭据领域中的值语义和相关操作。
    public struct LoadResult: Equatable, Sendable {
        public var value: String
        public var shouldRedactLegacy: Bool

        /// 创建 `LoadResult`，保存传入依赖并建立初始状态。
        public init(value: String, shouldRedactLegacy: Bool) {
            self.value = value
            self.shouldRedactLegacy = shouldRedactLegacy
        }
    }

    private let store: EncryptedCredentialStore
    private let legacyReader: any LegacyCredentialReading
    private let deviceID: String
    private let now: @Sendable () -> Date

    /// 创建 `CredentialAccessCoordinator`，保存传入依赖并建立初始状态。
    public init(
        store: EncryptedCredentialStore,
        legacyReader: any LegacyCredentialReading,
        deviceID: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.legacyReader = legacyReader
        self.deviceID = deviceID
        self.now = now
    }

    /// 读取并返回 `load` 对应的设置与凭据领域数据。
    public func load(
        _ key: CredentialKey,
        fallback: String
    ) throws -> LoadResult {
        let normalizedFallback = fallback.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if let record = try store.readRecord(for: key) {
            try markMigrationCompleteIfNeeded()
            return LoadResult(
                value: record.value ?? "",
                shouldRedactLegacy: !normalizedFallback.isEmpty
            )
        }
        if try store.isMigrationComplete() {
            return LoadResult(
                value: "",
                shouldRedactLegacy: !normalizedFallback.isEmpty
            )
        }
        if !normalizedFallback.isEmpty {
            let result = try store.update(
                value: normalizedFallback,
                for: key,
                deviceID: deviceID,
                updatedAt: now()
            )
            guard result.record.value == normalizedFallback else {
                throw CredentialAccessError.migrationVerificationFailed
            }
            try? store.markMigrationComplete()
            return LoadResult(
                value: normalizedFallback,
                shouldRedactLegacy: true
            )
        }

        let legacyValue = try legacyReader.read(key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let legacyValue, !legacyValue.isEmpty else {
            try store.markMigrationComplete()
            return LoadResult(value: "", shouldRedactLegacy: false)
        }
        let result = try store.update(
            value: legacyValue,
            for: key,
            deviceID: deviceID,
            updatedAt: now()
        )
        guard result.record.value == legacyValue else {
            throw CredentialAccessError.migrationVerificationFailed
        }
        try? store.markMigrationComplete()
        return LoadResult(value: legacyValue, shouldRedactLegacy: false)
    }

    /// 读取并返回 `loadLocal` 对应的设置与凭据领域数据。
    public func loadLocal(
        _ key: CredentialKey,
        fallback: String
    ) throws -> LoadResult? {
        let shouldRedactLegacy = !fallback.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        if let record = try store.readRecord(for: key) {
            try markMigrationCompleteIfNeeded()
            return LoadResult(
                value: record.value ?? "",
                shouldRedactLegacy: shouldRedactLegacy
            )
        }
        guard try store.isMigrationComplete() else { return nil }
        return LoadResult(
            value: "",
            shouldRedactLegacy: shouldRedactLegacy
        )
    }

    /// 保存 `save` 接收的设置与凭据领域数据，并保持既有持久化约束。
    @discardableResult
    public func save(
        _ value: String,
        for key: CredentialKey
    ) throws -> CredentialEnvelopeRecord {
        let result = try store.update(
            value: value,
            for: key,
            deviceID: deviceID,
            updatedAt: now()
        )
        try? store.markMigrationComplete()
        return result.record
    }

    /// 提交 `markMigrationCompleteIfNeeded` 对应的设置与凭据领域状态，并记录后续流程所需的进度。
    private func markMigrationCompleteIfNeeded() throws {
        if try !store.isMigrationComplete() {
            try store.markMigrationComplete()
        }
    }
}
