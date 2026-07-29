// `PreferenceRepository` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import Foundation
import GRDB

/// 封装 `PreferenceDomainDocument` 在设置与凭据领域中的值语义和相关操作。
public struct PreferenceDomainDocument: Equatable, Sendable {
    public let domain: String
    public let value: Data
    public let clocks: [String: ClipboardFieldClock]
    public let updatedAt: Date

    /// 创建 `PreferenceDomainDocument`，保存传入依赖并建立初始状态。
    public init(
        domain: String,
        value: Data,
        clocks: [String: ClipboardFieldClock],
        updatedAt: Date
    ) {
        self.domain = domain
        self.value = value
        self.clocks = clocks
        self.updatedAt = updatedAt
    }
}

/// 管理 `PreferenceRepository` 在设置与凭据领域中的生命周期、依赖和可变状态。
public final class PreferenceRepository: @unchecked Sendable {
    public static let appDomain = "preferences.app"
    public static let accountDomains: [String] = domainKeys.map(\.domain)

    private static let domainKeys: [(domain: String, keys: [String])] = [
        ("preferences.hotkeys", [
            "mainPanelShortcut", "clipboardShortcut",
            "reservedTool2Shortcut", "reservedTool3Shortcut"
        ]),
        ("preferences.clipboard", ["clipboard"]),
        ("preferences.translation", ["translation"]),
        ("preferences.superRightClick", ["superRightClick"]),
        ("preferences.windowLayout", ["windowLayout"]),
        ("preferences.screenCapture", ["screenCapture"]),
        ("preferences.appearance", ["appearanceMode"]),
        ("preferences.sync", ["sync"])
    ]

    private let database: MacToolsDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 创建 `PreferenceRepository`，保存传入依赖并建立初始状态。
    public init(database: MacToolsDatabase) {
        self.database = database
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

    /// 从统一设置记录解码完整 AppSettings；尚未初始化时返回 nil。
    public func load() throws -> AppSettings? {
        try database.writer.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT value FROM preferences WHERE domain = ?",
                arguments: [Self.appDomain]
            ) else { return nil }
            return try decoder.decode(AppSettings.self, from: data)
        }
    }

    /// 保存账号级设置；设备同步开关保持现有值，并为实际变化的领域推进字段时钟。
    public func save(
        _ settings: AppSettings,
        at date: Date = Date(),
        enqueuesSyncChange: Bool = true
    ) throws {
        let data = try encodedSanitized(settings)
        try database.writer.write { db in
            try save(
                data: data,
                deviceSyncEnabled: nil,
                at: date,
                enqueuesSyncChange: enqueuesSyncChange,
                in: db
            )
        }
    }

    /// 同时保存账号级设置和显式设备同步开关，用于开启或关闭同步的单事务切换。
    public func save(
        _ settings: AppSettings,
        deviceSyncEnabled: Bool,
        at date: Date = Date(),
        enqueuesSyncChange: Bool = true
    ) throws {
        let data = try encodedSanitized(settings)
        try database.writer.write { db in
            try save(
                data: data,
                deviceSyncEnabled: deviceSyncEnabled,
                at: date,
                enqueuesSyncChange: enqueuesSyncChange,
                in: db
            )
        }
    }

    /// 导出指定设置领域及其字段时钟；未知或尚未保存的领域返回 nil。
    public func domainDocument(_ domain: String) throws -> PreferenceDomainDocument? {
        guard let keys = Self.domainKeys.first(where: { $0.domain == domain })?.keys else {
            return nil
        }
        return try database.writer.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT value FROM preferences WHERE domain = ?",
                arguments: [Self.appDomain]
            ) else { return nil }
            let root = try Self.jsonObject(data)
            let subset = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                root[key].map { (key, $0) }
            })
            let value = try JSONSerialization.data(withJSONObject: subset, options: [.sortedKeys])
            let clockRows = try Row.fetchAll(
                db,
                sql: """
                SELECT fieldPath, counter, deviceID, updatedAt
                FROM preference_field_clocks WHERE domain = ?
                """,
                arguments: [domain]
            )
            var clocks: [String: ClipboardFieldClock] = [:]
            var updatedAt = Date.distantPast
            for row in clockRows {
                clocks[row["fieldPath"]] = ClipboardFieldClock(
                    counter: row["counter"],
                    deviceID: row["deviceID"]
                )
                updatedAt = max(updatedAt, row["updatedAt"] as Date)
            }
            return PreferenceDomainDocument(
                domain: domain,
                value: value,
                clocks: clocks,
                updatedAt: updatedAt
            )
        }
    }

    /// 按字段逻辑时钟合并一个远端设置领域，同时保留设备级配置和独立凭据。
    public func applyRemoteDomain(
        _ document: PreferenceDomainDocument,
        at date: Date = Date()
    ) throws -> AppSettings {
        guard let keys = Self.domainKeys.first(where: { $0.domain == document.domain })?.keys else {
            throw PreferenceRepositoryError.unknownDomain(document.domain)
        }
        return try database.writer.write { db in
            guard let currentData = try Data.fetchOne(
                db,
                sql: "SELECT value FROM preferences WHERE domain = ?",
                arguments: [Self.appDomain]
            ) else {
                throw PreferenceRepositoryError.missingSettings
            }
            var root = try Self.jsonObject(currentData)
            let remoteRoot = try Self.jsonObject(document.value)
            let localClocks = try fieldClocks(domain: document.domain, in: db)
            let localSubset = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                root[key].map { (key, $0) }
            })
            let mergedSubset = Self.merge(
                local: localSubset,
                remote: remoteRoot,
                path: "",
                localClocks: localClocks,
                remoteClocks: document.clocks
            ) as? [String: Any] ?? localSubset
            for key in keys {
                if let value = mergedSubset[key] { root[key] = value }
            }
            let mergedData = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            let settings = try decoder.decode(AppSettings.self, from: mergedData)
            try upsertPreference(data: mergedData, at: date, in: db)
            for (path, remoteClock) in document.clocks {
                let localClock = localClocks[path] ?? .zero
                guard remoteClock.wins(over: localClock) else { continue }
                try upsertClock(
                    domain: document.domain,
                    path: path,
                    clock: remoteClock,
                    at: document.updatedAt,
                    in: db
                )
            }
            return settings
        }
    }

    /// 返回统一设置记录的原始 JSON，供迁移和诊断测试使用。
    public func rawData() throws -> Data? {
        try database.writer.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value FROM preferences WHERE domain = ?",
                arguments: [Self.appDomain]
            )
        }
    }

    /// 在单一 GRDB 事务更新设置、设备开关、字段时钟和同步 outbox。
    private func save(
        data: Data,
        deviceSyncEnabled: Bool?,
        at date: Date,
        enqueuesSyncChange: Bool,
        in db: Database
    ) throws {
        let previousData = try Data.fetchOne(
            db,
            sql: "SELECT value FROM preferences WHERE domain = ?",
            arguments: [Self.appDomain]
        )
        try upsertPreference(data: data, at: date, in: db)
        if let deviceSyncEnabled {
            try db.execute(
                sql: """
                INSERT INTO device_overrides (key, value, updatedAt)
                VALUES ('sync.isEnabled', ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                """,
                arguments: [try encoder.encode(deviceSyncEnabled), date]
            )
        }
        let oldRoot = try previousData.map(Self.jsonObject)
            ?? Self.jsonObject(encodedSanitized(.defaults))
        let newRoot = try Self.jsonObject(data)
        var deviceID: String?
        for mapping in Self.domainKeys {
            let oldSubset = Dictionary(uniqueKeysWithValues: mapping.keys.compactMap { key in
                oldRoot[key].map { (key, $0) }
            })
            let newSubset = Dictionary(uniqueKeysWithValues: mapping.keys.compactMap { key in
                newRoot[key].map { (key, $0) }
            })
            let changedPaths = Self.changedLeafPaths(old: oldSubset, new: newSubset, path: "")
            guard !changedPaths.isEmpty else { continue }
            if deviceID == nil { deviceID = try self.deviceID(in: db) }
            for path in changedPaths {
                let current = try Int64.fetchOne(
                    db,
                    sql: """
                    SELECT counter FROM preference_field_clocks
                    WHERE domain = ? AND fieldPath = ?
                    """,
                    arguments: [mapping.domain, path]
                ) ?? 0
                try upsertClock(
                    domain: mapping.domain,
                    path: path,
                    clock: ClipboardFieldClock(counter: current + 1, deviceID: deviceID ?? ""),
                    at: date,
                    in: db
                )
            }
            if enqueuesSyncChange {
                try enqueueDomain(mapping.domain, at: date, in: db)
            }
        }
    }

    /// 清除 API Key 等设备或独立存储字段后编码可持久化账号设置。
    private func encodedSanitized(_ settings: AppSettings) throws -> Data {
        var sanitized = settings
        sanitized.translation.apiKey = ""
        sanitized.sync.isEnabled = false
        sanitized.clipboard.cacheStoragePath = ""
        sanitized.clipboard.maxCacheMegabytes = ClipboardCacheLimit.defaultMegabytes
        return try encoder.encode(sanitized)
    }

    /// 覆盖写入唯一设置记录及更新时间，不改变字段时钟。
    private func upsertPreference(data: Data, at date: Date, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO preferences (domain, value, schemaVersion, updatedAt)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(domain) DO UPDATE SET
                value = excluded.value,
                schemaVersion = excluded.schemaVersion,
                updatedAt = excluded.updatedAt
            """,
            arguments: [Self.appDomain, data, date]
        )
    }

    /// 读取指定领域每个叶子字段的逻辑时钟，缺失字段使用零时钟。
    private func fieldClocks(
        domain: String,
        in db: Database
    ) throws -> [String: ClipboardFieldClock] {
        try Row.fetchAll(
            db,
            sql: "SELECT fieldPath, counter, deviceID FROM preference_field_clocks WHERE domain = ?",
            arguments: [domain]
        ).reduce(into: [:]) { result, row in
            result[row["fieldPath"]] = ClipboardFieldClock(
                counter: row["counter"],
                deviceID: row["deviceID"]
            )
        }
    }

    /// 覆盖写入单个设置叶子字段的逻辑时钟和值摘要。
    private func upsertClock(
        domain: String,
        path: String,
        clock: ClipboardFieldClock,
        at date: Date,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO preference_field_clocks (
                domain, fieldPath, counter, deviceID, updatedAt
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(domain, fieldPath) DO UPDATE SET
                counter = excluded.counter,
                deviceID = excluded.deviceID,
                updatedAt = excluded.updatedAt
            """,
            arguments: [domain, path, clock.counter, clock.deviceID, date]
        )
    }

    /// 将设置领域加入同步 outbox，合并同一领域的重复本地变更。
    private func enqueueDomain(_ domain: String, at date: Date, in db: Database) throws {
        let generation = try Int.fetchOne(
            db,
            sql: "SELECT COALESCE(MAX(resetGeneration), 1) FROM sync_accounts"
        ) ?? 1
        try db.execute(
            sql: """
            INSERT INTO sync_outbox (
                recordType, recordName, operation, generation, createdAt, attemptCount
            ) VALUES (?, ?, 'save', ?, ?, 0)
            ON CONFLICT(recordType, recordName) DO UPDATE SET
                operation = excluded.operation,
                generation = excluded.generation,
                createdAt = excluded.createdAt,
                attemptCount = 0,
                lastError = NULL
            """,
            arguments: [SyncRecordType.preferenceDomain.rawValue, domain, generation, date]
        )
    }

    /// 读取或创建本机设备标识，作为设置字段时钟的稳定胜负键。
    private func deviceID(in db: Database) throws -> String {
        if let data = try Data.fetchOne(
            db,
            sql: "SELECT value FROM device_overrides WHERE key = 'sync.deviceID'"
        ), let value = try? decoder.decode(String.self, from: data) {
            return value
        }
        let value = UUID().uuidString
        try db.execute(
            sql: "INSERT INTO device_overrides (key, value, updatedAt) VALUES ('sync.deviceID', ?, ?)",
            arguments: [try encoder.encode(value), Date()]
        )
        return value
    }

    /// 解析并校验 `jsonObject` 接收的数据，返回设置与凭据领域可用的结构。
    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PreferenceRepositoryError.invalidJSON
        }
        return value
    }

    /// 递归比较 JSON 树并返回发生语义变化的叶子路径集合。
    private static func changedLeafPaths(old: Any?, new: Any?, path: String) -> Set<String> {
        if let old = old as? [String: Any], let new = new as? [String: Any] {
            return Set(old.keys).union(new.keys).reduce(into: []) { result, key in
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                result.formUnion(changedLeafPaths(old: old[key], new: new[key], path: childPath))
            }
        }
        if Self.jsonEqual(old, new) { return [] }
        return [path]
    }

    /// 递归合并设置 JSON；叶子字段仅由对应字段时钟决定远端或本地值胜出。
    private static func merge(
        local: Any?,
        remote: Any?,
        path: String,
        localClocks: [String: ClipboardFieldClock],
        remoteClocks: [String: ClipboardFieldClock]
    ) -> Any? {
        if let local = local as? [String: Any], let remote = remote as? [String: Any] {
            var result: [String: Any] = [:]
            for key in Set(local.keys).union(remote.keys) {
                let childPath = path.isEmpty ? key : "\(path).\(key)"
                if let value = merge(
                    local: local[key], remote: remote[key], path: childPath,
                    localClocks: localClocks, remoteClocks: remoteClocks
                ) {
                    result[key] = value
                }
            }
            return result
        }
        // 缺少时钟的旧字段按 zero 处理；相同时钟保守保留本地值。
        let localClock = localClocks[path] ?? .zero
        let remoteClock = remoteClocks[path] ?? .zero
        return remoteClock.wins(over: localClock) ? remote : local
    }

    /// 解析并校验 `jsonEqual` 接收的数据，返回设置与凭据领域可用的结构。
    private static func jsonEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs as NSObject, rhs as NSObject): return lhs == rhs
        default: return false
        }
    }
}

/// 描述 `PreferenceRepositoryError` 在设置与凭据领域中可取的状态、选项或错误。
public enum PreferenceRepositoryError: Error, Equatable {
    case unknownDomain(String)
    case missingSettings
    case invalidJSON
}
