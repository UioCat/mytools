// `DeviceOverrideRepository` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import Foundation
import GRDB

/// 管理 `DeviceOverrideRepository` 在设置与凭据领域中的生命周期、依赖和可变状态。
public final class DeviceOverrideRepository: @unchecked Sendable {
    /// 描述 `Key` 在设置与凭据领域中可取的状态、选项或错误。
    enum Key {
        static let syncEnabled = "sync.isEnabled"
        static let deviceID = "sync.deviceID"
        static let folderBookmark = "sync.folderBookmark"
        static let folderDisplayPath = "sync.folderDisplayPath"
        static let storeID = "sync.storeID"
        static let replicaRevision = "sync.replicaRevision"
        static let seenRevisions = "sync.seenRevisions"
    }

    private let database: MacToolsDatabase

    /// 创建 `DeviceOverrideRepository`，保存传入依赖并建立初始状态。
    public init(database: MacToolsDatabase) {
        self.database = database
    }

    /// 判断 `isSyncEnabled` 所描述的设置与凭据领域条件是否成立。
    public func isSyncEnabled() throws -> Bool {
        try value(for: Key.syncEnabled, as: Bool.self) ?? false
    }

    /// 计算并返回 `deviceID` 对应的设置与凭据领域数据或状态结果。
    public func deviceID() throws -> UUID {
        if let value = try value(for: Key.deviceID, as: String.self),
           let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        try setValue(id.uuidString, for: Key.deviceID)
        return id
    }

    /// 调整 `rotateDeviceID` 涉及的设置与凭据领域状态，并保持迁移或恢复语义。
    public func rotateDeviceID() throws -> UUID {
        let id = UUID()
        try setValue(id.uuidString, for: Key.deviceID)
        try setReplicaRevision(0)
        try setSeenRevisions([:])
        return id
    }

    /// 对账或合并 `syncFolderBookmark` 涉及的设置与凭据领域状态，并返回收敛结果。
    public func syncFolderBookmark() throws -> Data? {
        try value(for: Key.folderBookmark, as: Data.self)
    }

    /// 对账或合并 `syncFolderDisplayPath` 涉及的设置与凭据领域状态，并返回收敛结果。
    public func syncFolderDisplayPath() throws -> String? {
        try value(for: Key.folderDisplayPath, as: String.self)
    }

    /// 应用 `setSyncFolder` 接收的新值，并更新相关设置与凭据领域状态。
    public func setSyncFolder(bookmark: Data, displayPath: String) throws {
        try database.writer.write { db in
            let encoder = JSONEncoder()
            let date = Date()
            try Self.upsert(encoder.encode(bookmark), for: Key.folderBookmark, at: date, in: db)
            try Self.upsert(encoder.encode(displayPath), for: Key.folderDisplayPath, at: date, in: db)
        }
    }

    /// 保存 `storeID` 接收的设置与凭据领域数据，并保持既有持久化约束。
    public func storeID() throws -> UUID? {
        guard let value = try value(for: Key.storeID, as: String.self) else { return nil }
        return UUID(uuidString: value)
    }

    /// 应用 `setStoreID` 接收的新值，并更新相关设置与凭据领域状态。
    public func setStoreID(_ storeID: UUID) throws {
        try setValue(storeID.uuidString, for: Key.storeID)
    }

    /// 计算并返回 `replicaRevision` 对应的设置与凭据领域数据或状态结果。
    public func replicaRevision() throws -> Int64 {
        try value(for: Key.replicaRevision, as: Int64.self) ?? 0
    }

    /// 应用 `setReplicaRevision` 接收的新值，并更新相关设置与凭据领域状态。
    public func setReplicaRevision(_ revision: Int64) throws {
        try setValue(max(0, revision), for: Key.replicaRevision)
    }

    /// 计算并返回 `seenRevisions` 对应的设置与凭据领域数据或状态结果。
    public func seenRevisions() throws -> [String: Int64] {
        try value(for: Key.seenRevisions, as: [String: Int64].self) ?? [:]
    }

    /// 应用 `setSeenRevisions` 接收的新值，并更新相关设置与凭据领域状态。
    public func setSeenRevisions(_ revisions: [String: Int64]) throws {
        try setValue(revisions, for: Key.seenRevisions)
    }

    /// 在外层数据库事务内同时保存本机 revision 与向量时钟。
    static func setSyncProgress(
        revision: Int64,
        seenRevisions: [String: Int64],
        at date: Date,
        in db: Database
    ) throws {
        let encoder = JSONEncoder()
        try upsert(
            encoder.encode(max(0, revision)),
            for: Key.replicaRevision,
            at: date,
            in: db
        )
        try upsert(
            encoder.encode(seenRevisions),
            for: Key.seenRevisions,
            at: date,
            in: db
        )
    }

    /// 计算并返回 `value` 对应的设置与凭据领域数据或状态结果。
    private func value<Value: Decodable>(for key: String, as type: Value.Type) throws -> Value? {
        try database.writer.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT value FROM device_overrides WHERE key = ?",
                arguments: [key]
            ) else {
                return nil
            }
            return try JSONDecoder().decode(Value.self, from: data)
        }
    }

    /// 应用 `setValue` 接收的新值，并更新相关设置与凭据领域状态。
    private func setValue<Value: Encodable>(_ value: Value, for key: String) throws {
        let data = try JSONEncoder().encode(value)
        try database.writer.write { db in
            try Self.upsert(data, for: key, at: Date(), in: db)
        }
    }

    /// 保存 `upsert` 接收的设置与凭据领域数据，并保持既有持久化约束。
    private static func upsert(
        _ data: Data,
        for key: String,
        at date: Date,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO device_overrides (key, value, updatedAt)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
            """,
            arguments: [key, data, date]
        )
    }
}
