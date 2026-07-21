import Foundation
import GRDB

public final class DeviceOverrideRepository: @unchecked Sendable {
    private enum Key {
        static let syncEnabled = "sync.isEnabled"
        static let deviceID = "sync.deviceID"
        static let folderBookmark = "sync.folderBookmark"
        static let folderDisplayPath = "sync.folderDisplayPath"
        static let storeID = "sync.storeID"
        static let replicaRevision = "sync.replicaRevision"
        static let seenRevisions = "sync.seenRevisions"
    }

    private let database: MacToolsDatabase

    public init(database: MacToolsDatabase) {
        self.database = database
    }

    public func isSyncEnabled() throws -> Bool {
        try value(for: Key.syncEnabled, as: Bool.self) ?? false
    }

    public func setSyncEnabled(_ isEnabled: Bool) throws {
        try setValue(isEnabled, for: Key.syncEnabled)
    }

    public func deviceID() throws -> UUID {
        if let value = try value(for: Key.deviceID, as: String.self),
           let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        try setValue(id.uuidString, for: Key.deviceID)
        return id
    }

    public func rotateDeviceID() throws -> UUID {
        let id = UUID()
        try setValue(id.uuidString, for: Key.deviceID)
        try setReplicaRevision(0)
        try setSeenRevisions([:])
        return id
    }

    public func syncFolderBookmark() throws -> Data? {
        try value(for: Key.folderBookmark, as: Data.self)
    }

    public func syncFolderDisplayPath() throws -> String? {
        try value(for: Key.folderDisplayPath, as: String.self)
    }

    public func setSyncFolder(bookmark: Data, displayPath: String) throws {
        try database.writer.write { db in
            let encoder = JSONEncoder()
            try upsert(encoder.encode(bookmark), for: Key.folderBookmark, in: db)
            try upsert(encoder.encode(displayPath), for: Key.folderDisplayPath, in: db)
        }
    }

    public func storeID() throws -> UUID? {
        guard let value = try value(for: Key.storeID, as: String.self) else { return nil }
        return UUID(uuidString: value)
    }

    public func setStoreID(_ storeID: UUID) throws {
        try setValue(storeID.uuidString, for: Key.storeID)
    }

    public func replicaRevision() throws -> Int64 {
        try value(for: Key.replicaRevision, as: Int64.self) ?? 0
    }

    public func setReplicaRevision(_ revision: Int64) throws {
        try setValue(max(0, revision), for: Key.replicaRevision)
    }

    public func seenRevisions() throws -> [String: Int64] {
        try value(for: Key.seenRevisions, as: [String: Int64].self) ?? [:]
    }

    public func setSeenRevisions(_ revisions: [String: Int64]) throws {
        try setValue(revisions, for: Key.seenRevisions)
    }

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

    private func setValue<Value: Encodable>(_ value: Value, for key: String) throws {
        let data = try JSONEncoder().encode(value)
        try database.writer.write { db in
            try upsert(data, for: key, in: db)
        }
    }

    private func upsert(_ data: Data, for key: String, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO device_overrides (key, value, updatedAt)
            VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
            """,
            arguments: [key, data, Date()]
        )
    }
}
