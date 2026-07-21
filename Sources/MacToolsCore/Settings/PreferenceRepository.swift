import Foundation
import GRDB

public struct PreferenceDomainDocument: Equatable, Sendable {
    public let domain: String
    public let value: Data
    public let clocks: [String: ClipboardFieldClock]
    public let updatedAt: Date

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

    public init(database: MacToolsDatabase) {
        self.database = database
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
    }

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

    public func rawData() throws -> Data? {
        try database.writer.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value FROM preferences WHERE domain = ?",
                arguments: [Self.appDomain]
            )
        }
    }

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

    private func encodedSanitized(_ settings: AppSettings) throws -> Data {
        var sanitized = settings
        sanitized.translation.apiKey = ""
        sanitized.sync.isEnabled = false
        sanitized.clipboard.cacheStoragePath = ""
        sanitized.clipboard.maxCacheMegabytes = ClipboardCacheLimit.defaultMegabytes
        return try encoder.encode(sanitized)
    }

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

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PreferenceRepositoryError.invalidJSON
        }
        return value
    }

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
        let localClock = localClocks[path] ?? .zero
        let remoteClock = remoteClocks[path] ?? .zero
        return remoteClock.wins(over: localClock) ? remote : local
    }

    private static func jsonEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs as NSObject, rhs as NSObject): return lhs == rhs
        default: return false
        }
    }
}

public enum PreferenceRepositoryError: Error, Equatable {
    case unknownDomain(String)
    case missingSettings
    case invalidJSON
}
