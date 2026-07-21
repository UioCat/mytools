import Foundation
import GRDB

public enum UnifiedStoreBootstrapError: Error {
    case databaseIntegrityCheckFailed
    case foreignKeyCheckFailed
    case missingPayloadObjects(Int)
    case stagedStoreWasNotInstalled
}

public struct UnifiedStoreBootstrapResult: Equatable {
    public let migrationReport: LegacyStoreMigrationReport
    public let didCutOver: Bool
    public let rollbackDirectory: URL?
}

/// Builds and verifies the complete store outside the live path before switching
/// directories. Legacy sources and incomplete stores are preserved for rollback.
public enum UnifiedStoreBootstrapper {
    public static let cutoverMigrationKey = "unified-store-cutover-v1"

    public static func prepare(
        paths: MacToolsStorePaths,
        legacySettings: AppSettings,
        fileManager: FileManager = .default
    ) throws -> UnifiedStoreBootstrapResult {
        if try hasCutoverMarker(at: paths.databaseURL) {
            let database = try MacToolsDatabase.at(paths.databaseURL)
            return UnifiedStoreBootstrapResult(
                migrationReport: try completedLegacyReport(in: database) ?? LegacyStoreMigrationReport(),
                didCutOver: false,
                rollbackDirectory: nil
            )
        }

        let stagingDirectory = paths.supportDirectory
            .appendingPathComponent("Store.migrating", isDirectory: true)
        let stagedPaths = MacToolsStorePaths(
            supportDirectory: paths.supportDirectory,
            storeDirectoryOverride: stagingDirectory
        )

        if try hasCutoverMarker(at: stagedPaths.databaseURL) {
            let rollbackDirectory = try installStagedStore(
                stagingDirectory,
                at: paths.storeDirectory,
                fileManager: fileManager
            )
            guard try hasCutoverMarker(at: paths.databaseURL) else {
                throw UnifiedStoreBootstrapError.stagedStoreWasNotInstalled
            }
            let database = try MacToolsDatabase.at(paths.databaseURL)
            return UnifiedStoreBootstrapResult(
                migrationReport: try completedLegacyReport(in: database) ?? LegacyStoreMigrationReport(),
                didCutOver: true,
                rollbackDirectory: rollbackDirectory
            )
        }

        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try SensitiveFilePermissions.prepareDirectory(at: stagingDirectory)

        let report = try buildAndVerifyStagedStore(
            paths: stagedPaths,
            legacyPaths: paths,
            legacySettings: legacySettings,
            fileManager: fileManager
        )
        let rollbackDirectory = try installStagedStore(
            stagingDirectory,
            at: paths.storeDirectory,
            fileManager: fileManager
        )
        guard try hasCutoverMarker(at: paths.databaseURL) else {
            throw UnifiedStoreBootstrapError.stagedStoreWasNotInstalled
        }
        return UnifiedStoreBootstrapResult(
            migrationReport: report,
            didCutOver: true,
            rollbackDirectory: rollbackDirectory
        )
    }

    private static func buildAndVerifyStagedStore(
        paths: MacToolsStorePaths,
        legacyPaths: MacToolsStorePaths,
        legacySettings: AppSettings,
        fileManager: FileManager
    ) throws -> LegacyStoreMigrationReport {
        let database = try MacToolsDatabase.at(paths.databaseURL)
        let payloadStore = PayloadStore(rootDirectory: paths.payloadsDirectory, fileManager: fileManager)
        let repository = ClipboardRepository(database: database, payloadStore: payloadStore)
        let preferenceRepository = PreferenceRepository(database: database)
        let migrationDeviceID = try DeviceOverrideRepository(database: database).deviceID().uuidString

        try preferenceRepository.save(legacySettings, enqueuesSyncChange: false)
        let report = try LegacyStoreMigrator(
            database: database,
            repository: repository,
            payloadStore: payloadStore,
            migrationDeviceID: migrationDeviceID,
            fileManager: fileManager
        ).migrateClipboardIfNeeded(
            from: legacyPaths.legacyDatabaseURL,
            enqueuesSyncChanges: false
        )
        try recoverIncompleteUnifiedStoreIfPresent(
            sourcePaths: legacyPaths,
            targetRepository: repository,
            targetPreferences: preferenceRepository,
            fileManager: fileManager
        )
        try payloadStore.removeStagingFiles()
        try validate(database: database, payloadStore: payloadStore, fileManager: fileManager)
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO migration_state (key, completedAt, details)
                VALUES (?, ?, NULL)
                ON CONFLICT(key) DO UPDATE SET completedAt = excluded.completedAt
                """,
                arguments: [cutoverMigrationKey, Date()]
            )
        }
        return report
    }

    private static func recoverIncompleteUnifiedStoreIfPresent(
        sourcePaths: MacToolsStorePaths,
        targetRepository: ClipboardRepository,
        targetPreferences: PreferenceRepository,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: sourcePaths.databaseURL.path) else { return }
        let recoveryDirectory = sourcePaths.supportDirectory.appendingPathComponent(
            "Store.recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.copyItem(at: sourcePaths.storeDirectory, to: recoveryDirectory)
        defer { try? fileManager.removeItem(at: recoveryDirectory) }
        let recoveryPaths = MacToolsStorePaths(
            supportDirectory: sourcePaths.supportDirectory,
            storeDirectoryOverride: recoveryDirectory
        )
        let sourceDatabase: MacToolsDatabase
        do {
            sourceDatabase = try MacToolsDatabase.at(recoveryPaths.databaseURL)
        } catch {
            return
        }
        let sourcePayloadStore = PayloadStore(rootDirectory: recoveryPaths.payloadsDirectory)
        let sourceRepository = ClipboardRepository(
            database: sourceDatabase,
            payloadStore: sourcePayloadStore
        )
        if let sourceSettings = try PreferenceRepository(database: sourceDatabase).load() {
            try targetPreferences.save(sourceSettings, enqueuesSyncChange: false)
        }
        for item in try sourceRepository.search("", limit: 1_000_000) {
            if item.kind == .imageData {
                guard let path = item.cachedFilePath,
                      fileManager.fileExists(atPath: path) else { continue }
                do {
                    try targetRepository.upsertPNG(
                        item,
                        data: try Data(contentsOf: URL(fileURLWithPath: path)),
                        enqueuesSyncChange: false
                    )
                } catch is PayloadStoreError {
                    continue
                }
            } else {
                try targetRepository.upsert(item, enqueuesSyncChange: false)
            }
        }
    }

    private static func validate(
        database: MacToolsDatabase,
        payloadStore: PayloadStore,
        fileManager: FileManager
    ) throws {
        let integrity: String? = try database.writer.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check")
        }
        guard integrity == "ok" else {
            throw UnifiedStoreBootstrapError.databaseIntegrityCheckFailed
        }
        let foreignKeyFailures = try database.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
        }
        guard foreignKeyFailures == 0 else {
            throw UnifiedStoreBootstrapError.foreignKeyCheckFailed
        }
        let relativePaths: [String] = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT relativePath FROM payload_objects")
        }
        let missingCount = relativePaths.reduce(into: 0) { count, relativePath in
            guard let fileURL = payloadStore.fileURL(for: relativePath),
                  fileManager.fileExists(atPath: fileURL.path) else {
                count += 1
                return
            }
        }
        guard missingCount == 0 else {
            throw UnifiedStoreBootstrapError.missingPayloadObjects(missingCount)
        }
    }

    private static func hasCutoverMarker(at databaseURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return false
        }
        do {
            var configuration = Configuration()
            configuration.readonly = true
            let database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            return try database.read { db in
                guard try db.tableExists("migration_state") else { return false }
                return try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM migration_state WHERE key = ?)",
                    arguments: [cutoverMigrationKey]
                ) ?? false
            }
        } catch {
            return false
        }
    }

    private static func completedLegacyReport(
        in database: MacToolsDatabase
    ) throws -> LegacyStoreMigrationReport? {
        try database.writer.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT details FROM migration_state WHERE key = ?",
                arguments: [LegacyStoreMigrator.migrationKey]
            ) else {
                return nil
            }
            return try JSONDecoder().decode(LegacyStoreMigrationReport.self, from: data)
        }
    }

    private static func installStagedStore(
        _ stagingDirectory: URL,
        at destinationDirectory: URL,
        fileManager: FileManager
    ) throws -> URL? {
        var rollbackDirectory: URL?
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            let backup = destinationDirectory
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Store.rollback-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)",
                    isDirectory: true
                )
            try fileManager.moveItem(at: destinationDirectory, to: backup)
            rollbackDirectory = backup
        }
        do {
            try fileManager.moveItem(at: stagingDirectory, to: destinationDirectory)
        } catch {
            if let rollbackDirectory,
               !fileManager.fileExists(atPath: destinationDirectory.path) {
                try? fileManager.moveItem(at: rollbackDirectory, to: destinationDirectory)
            }
            throw error
        }
        return rollbackDirectory
    }
}
