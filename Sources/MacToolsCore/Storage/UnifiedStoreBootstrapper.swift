// `UnifiedStoreBootstrapper` 的本地存储领域实现。
// 负责数据库、载荷文件和迁移事务，不管理运行时面板状态。

import Foundation
import GRDB

/// 描述 `UnifiedStoreBootstrapError` 在本地存储领域中可取的状态、选项或错误。
public enum UnifiedStoreBootstrapError: Error {
    case databaseIntegrityCheckFailed
    case foreignKeyCheckFailed
    case missingPayloadObjects(Int)
    case stagedStoreWasNotInstalled
}

/// 封装 `UnifiedStoreBootstrapResult` 在本地存储领域中的值语义和相关操作。
public struct UnifiedStoreBootstrapResult: Equatable {
    public let migrationReport: LegacyStoreMigrationReport
    public let didCutOver: Bool
    public let rollbackDirectory: URL?
}

/// 在当前生效路径之外构建并校验完整 Store，再切换目录。
/// 旧迁移源和未完成 Store 会保留为回滚依据。
public enum UnifiedStoreBootstrapper {
    public static let cutoverMigrationKey = "unified-store-cutover-v1"

    /// 复用已完成 Store，或在 staging 中迁移并校验后切换到统一 Store。
    public static func prepare(
        paths: MacToolsStorePaths,
        legacySettings: AppSettings,
        fileManager: FileManager = .default
    ) throws -> UnifiedStoreBootstrapResult {
        // cutover 标记只会在完整校验后写入；存在标记即可直接复用当前 Store。
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

        // 上次启动可能在安装前退出；已完成的 staging 可以直接继续切换，无需重复迁移。
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

    /// 在隔离目录完成设置、剪贴板和载荷迁移，校验通过后写入 cutover 标记。
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

    /// 调整 `recoverIncompleteUnifiedStoreIfPresent` 涉及的本地存储领域状态，并保持迁移或恢复语义。
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

    /// 校验 `validate` 接收的本地存储领域数据是否满足当前约束。
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

    /// 判断 `hasCutoverMarker` 所描述的本地存储领域条件是否成立。
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

    /// 结束 `completedLegacyReport` 对应的本地存储领域流程，并释放或重置相关资源。
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

    /// 先把当前 Store 移为 rollback，再安装 staging；安装失败时尽力恢复原 Store。
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
