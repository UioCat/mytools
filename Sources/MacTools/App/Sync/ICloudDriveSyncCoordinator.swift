// `ICloudDriveSyncCoordinator` 的 iCloud Drive 同步系统集成实现。
// 负责文件协调、下载请求和后台调度，不定义同步合并规则。

import Foundation
import MacToolsCore

/// 管理 `ICloudDriveSyncCoordinator` 在 iCloud Drive 同步系统集成中的生命周期、依赖和可变状态。
final class ICloudDriveSyncCoordinator: @unchecked Sendable {
    /// 为iCloud Drive 同步系统集成中的相关类型提供 `StatusHandler` 别名。
    typealias StatusHandler = @Sendable (SyncStatus) -> Void
    /// 为iCloud Drive 同步系统集成中的相关类型提供 `RemoteSettingsHandler` 别名。
    typealias RemoteSettingsHandler = @Sendable (AppSettings) -> Void
    /// 为iCloud Drive 同步系统集成中的相关类型提供 `DevicesHandler` 别名。
    typealias DevicesHandler = @Sendable ([SyncDeviceSummary]) -> Void
    /// 为iCloud Drive 同步系统集成中的相关类型提供 `CredentialStateHandler` 别名。
    typealias CredentialStateHandler = @Sendable (CredentialCloudState) -> Void

    /// 描述 `CredentialCloudState` 在 iCloud Drive 同步系统集成中可取的状态、选项或错误。
    enum CredentialCloudState: Sendable {
        case record(CredentialEnvelopeRecord)
        case noRecord
        case waitingForDownload
        case unavailable
        case failed
    }

    /// 封装 `Configuration` 在 iCloud Drive 同步系统集成中的值语义和相关操作。
    private struct Configuration {
        var isEnabled = false
        var rootURL: URL?
        var historyLimit: Int
        var clipboardScope: ClipboardSyncScope
        var storageLimit: SyncStorageLimit
        var scheduleToken: UInt64 = 0

        var cycleConfiguration: DriveSyncCycleConfiguration {
            DriveSyncCycleConfiguration(
                historyLimit: historyLimit,
                clipboardScope: clipboardScope,
                storageLimit: storageLimit
            )
        }
    }

    /// 标识一次同步请求读取到的目录和生命周期代际。
    private struct CycleLease {
        var token: UInt64
        var rootURL: URL
    }

    /// 描述一次周期结束后调度器应执行的动作。
    private enum CycleCompletion {
        case finish
        case rerun
        case schedule(UInt64)
    }

    private let localRepository: SyncLocalRepository
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let cycleRunner: DriveSyncCycleRunner
    private let credentialSyncEngine: CredentialSyncEngine
    private let statusHandler: StatusHandler
    private let remoteSettingsHandler: RemoteSettingsHandler
    private let devicesHandler: DevicesHandler
    private let credentialStateHandler: CredentialStateHandler
    private let queue = DispatchQueue(label: "com.mactools.icloud-drive-sync", qos: .utility)
    private let lock = NSLock()
    private var configuration: Configuration
    private var isSyncing = false
    private var needsAnotherCycle = false

    /// 创建 `ICloudDriveSyncCoordinator`，保存传入依赖并建立初始状态。
    init(
        localRepository: SyncLocalRepository,
        deviceOverrideRepository: DeviceOverrideRepository,
        payloadStore: PayloadStore,
        encryptedCredentialStore: EncryptedCredentialStore,
        historyLimit: Int,
        clipboardScope: ClipboardSyncScope,
        storageLimit: SyncStorageLimit,
        rootURL: URL?,
        statusHandler: @escaping StatusHandler,
        remoteSettingsHandler: @escaping RemoteSettingsHandler,
        devicesHandler: @escaping DevicesHandler,
        credentialStateHandler: @escaping CredentialStateHandler
    ) {
        self.localRepository = localRepository
        self.deviceOverrideRepository = deviceOverrideRepository
        self.cycleRunner = DriveSyncCycleRunner(
            localRepository: localRepository,
            deviceOverrideRepository: deviceOverrideRepository,
            payloadStore: payloadStore,
            deviceName: { Host.current().localizedName },
            requestDownload: { url in
                try Self.requestDownloadIfNeeded(url)
            }
        )
        self.credentialSyncEngine = CredentialSyncEngine(localStore: encryptedCredentialStore)
        self.statusHandler = statusHandler
        self.remoteSettingsHandler = remoteSettingsHandler
        self.devicesHandler = devicesHandler
        self.credentialStateHandler = credentialStateHandler
        self.configuration = Configuration(
            rootURL: rootURL,
            historyLimit: historyLimit,
            clipboardScope: clipboardScope,
            storageLimit: storageLimit
        )
    }

    /// 更新同步开关并使既有周期令牌失效；运行中周期会在下一个协作检查点退出。
    func setEnabled(_ enabled: Bool, syncImmediately: Bool = true) {
        let snapshot = lock.withLock { () -> Configuration in
            configuration.isEnabled = enabled
            configuration.scheduleToken &+= 1
            return configuration
        }
        if !enabled {
            statusHandler(.off)
            return
        }
        guard snapshot.rootURL != nil else {
            statusHandler(.unconfigured)
            return
        }
        if syncImmediately {
            syncNow()
        }
    }

    /// 应用 `updateConfiguration` 接收的新值，并更新相关 iCloud Drive 同步系统集成状态。
    func updateConfiguration(
        historyLimit: Int,
        clipboardScope: ClipboardSyncScope,
        storageLimit: SyncStorageLimit
    ) {
        lock.withLock {
            configuration.historyLimit = historyLimit
            configuration.clipboardScope = clipboardScope
            configuration.storageLimit = storageLimit
            configuration.scheduleToken &+= 1
            if isSyncing {
                needsAnotherCycle = true
            }
        }
    }

    /// 应用 `setRootURL` 接收的新值，并更新相关 iCloud Drive 同步系统集成状态。
    func setRootURL(_ rootURL: URL?) {
        let enabled = lock.withLock { () -> Bool in
            configuration.rootURL = rootURL?.standardizedFileURL
            configuration.scheduleToken &+= 1
            return configuration.isEnabled
        }
        if rootURL == nil {
            statusHandler(.unconfigured)
        } else if enabled {
            syncNow()
        } else {
            statusHandler(.off)
        }
    }

    /// 合并并发同步请求：已有周期运行时只记录一次补跑需求。
    func syncNow() {
        let shouldStart = lock.withLock { () -> Bool in
            guard configuration.isEnabled else { return false }
            if isSyncing {
                needsAnotherCycle = true
                return false
            }
            isSyncing = true
            return true
        }
        guard shouldStart else { return }

        queue.async { [weak self] in
            self?.runCycles()
        }
    }

    /// 凭据优先执行完整同步，避免启动时重复安排凭据 bootstrap 和普通同步。
    func bootstrapCredentialAndSync() {
        syncNow()
    }

    /// 调整 `resetSyncData` 涉及的 iCloud Drive 同步系统集成状态，并保持迁移或恢复语义。
    func resetSyncData() {
        let snapshot = lock.withLock { configuration }
        guard let lease = cycleLease(for: snapshot) else { return }
        let cancellation = cancellation(for: lease)
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.withCoordinatedWrite(
                    at: lease.rootURL,
                    cancellation: cancellation
                ) { coordinatedRoot in
                    let store = DriveSyncStore(rootURL: coordinatedRoot)
                    let descriptor = try store.readProtocol()
                    try cancellation.check()
                    try self.localRepository.bindStore(descriptor.storeID)
                    let generation = try self.localRepository.advanceGeneration(
                        storeID: descriptor.storeID
                    )
                    let deviceID = try self.deviceOverrideRepository.deviceID().uuidString
                    try cancellation.check()
                    try store.writeReset(
                        SyncResetMarker(
                            deviceID: deviceID,
                            generation: generation,
                            resetAt: Date()
                        )
                    )
                    try self.deviceOverrideRepository.setReplicaRevision(0)
                    try self.deviceOverrideRepository.setSeenRevisions([:])
                }
                if self.isCurrent(lease) {
                    self.syncNow()
                }
            } catch is SyncCycleCancellationError {
                return
            } catch {
                self.publish(error, lease: lease)
            }
        }
    }

    /// 移除 `removeDevice` 指定的 iCloud Drive 同步系统集成数据，并维护关联状态。
    func removeDevice(_ removedDeviceID: String) {
        let snapshot = lock.withLock { configuration }
        guard let lease = cycleLease(for: snapshot) else { return }
        let cancellation = cancellation(for: lease)
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.withCoordinatedWrite(
                    at: lease.rootURL,
                    cancellation: cancellation
                ) { coordinatedRoot in
                    let store = DriveSyncStore(rootURL: coordinatedRoot)
                    let descriptor = try store.readProtocol()
                    try cancellation.check()
                    try self.localRepository.bindStore(descriptor.storeID)
                    let generation = try self.localRepository.currentGeneration(
                        storeID: descriptor.storeID
                    )
                    let removerDeviceID = try self.deviceOverrideRepository.deviceID().uuidString
                    guard removedDeviceID != removerDeviceID else { return }
                    let alreadyRemovedDeviceIDs = try store.removedDeviceIDs(
                        generation: generation
                    )
                    try cancellation.check()
                    _ = try self.credentialSyncEngine.synchronize(
                        rootURL: coordinatedRoot,
                        currentDeviceID: removerDeviceID,
                        removedDeviceIDs: alreadyRemovedDeviceIDs
                    )
                    try cancellation.check()
                    try self.localRepository.preserveTombstones(
                        fromRemovedDeviceID: removedDeviceID,
                        generation: generation
                    )
                    try cancellation.check()
                    try store.writeRemovedDevice(
                        SyncRemovedDeviceMarker(
                            removedDeviceID: removedDeviceID,
                            removerDeviceID: removerDeviceID,
                            generation: generation,
                            removedAt: Date()
                        )
                    )
                }
                if self.isCurrent(lease) {
                    self.syncNow()
                }
            } catch is SyncCycleCancellationError {
                return
            } catch {
                self.publish(error, lease: lease)
            }
        }
    }

    /// 串行执行同步周期，消费补跑标记后再安排下一次定时同步。
    private func runCycles() {
        while true {
            let snapshot = lock.withLock { configuration }
            guard snapshot.isEnabled else {
                finishSyncing()
                return
            }
            guard let lease = cycleLease(for: snapshot) else {
                statusHandler(.unconfigured)
                finishSyncing()
                return
            }
            let cancellation = cancellation(for: lease)

            do {
                try cancellation.check()
                statusHandler(.syncing)

                let credentialStatus: SyncStatus?
                do {
                    let credentialResult = try withCoordinatedWrite(
                        at: lease.rootURL,
                        cancellation: cancellation
                    ) { coordinatedRoot in
                        try synchronizeCredential(at: coordinatedRoot)
                    }
                    try cancellation.check()
                    credentialStatus = publishCredential(credentialResult)
                } catch is SyncCycleCancellationError {
                    throw SyncCycleCancellationError.cancelled
                } catch let error as DriveSyncStoreError {
                    try cancellation.check()
                    credentialStatus = publishCredential(error)
                } catch {
                    try cancellation.check()
                    credentialStateHandler(.failed)
                    credentialStatus = .failed
                }

                let driveResult = try withCoordinatedWrite(
                    at: lease.rootURL,
                    cancellation: cancellation
                ) { coordinatedRoot in
                    try cycleRunner.run(
                        rootURL: coordinatedRoot,
                        configuration: snapshot.cycleConfiguration,
                        cancellation: cancellation
                    )
                }
                try cancellation.check()
                if let settings = driveResult.remoteSettings {
                    remoteSettingsHandler(settings)
                }
                devicesHandler(driveResult.devices)
                statusHandler(credentialStatus ?? driveResult.status)
            } catch is SyncCycleCancellationError {
                // 关闭、切换目录或配置变化属于正常淘汰，不发布失败状态。
            } catch let error as DriveSyncStoreError {
                if isCurrent(lease) {
                    if case let .itemNotDownloaded(url) = error {
                        try? Self.requestDownloadIfNeeded(url)
                        statusHandler(.waitingForDownload)
                    } else if case .incompatibleProtocol = error {
                        statusHandler(.protocolIncompatible)
                    } else if case .missingProtocol = error {
                        statusHandler(.folderUnavailable)
                    } else {
                        statusHandler(.failed)
                    }
                }
            } catch {
                publish(error, lease: lease)
            }

            let completion = lock.withLock { () -> CycleCompletion in
                guard configuration.isEnabled else {
                    isSyncing = false
                    needsAnotherCycle = false
                    return .finish
                }
                if needsAnotherCycle || configuration.scheduleToken != lease.token {
                    needsAnotherCycle = false
                    return .rerun
                }
                let token = configuration.scheduleToken
                isSyncing = false
                return .schedule(token)
            }
            switch completion {
            case .finish:
                return
            case .rerun:
                continue
            case let .schedule(token):
                schedulePeriodicSync(token: token)
                return
            }
        }
    }

    /// 对账或合并 `synchronizeCredential` 涉及的 iCloud Drive 同步系统集成状态，并返回收敛结果。
    private func synchronizeCredential(at rootURL: URL) throws -> CredentialSyncResult {
        let store = DriveSyncStore(rootURL: rootURL)
        let descriptor = try store.readProtocol()
        try localRepository.bindStore(descriptor.storeID)
        let generation = try localRepository.currentGeneration(
            storeID: descriptor.storeID
        )
        let removedDeviceIDs = try store.removedDeviceIDs(generation: generation)
        let deviceID = try deviceOverrideRepository.deviceID().uuidString
        return try credentialSyncEngine.synchronize(
            rootURL: rootURL,
            currentDeviceID: deviceID,
            removedDeviceIDs: removedDeviceIDs
        )
    }

    /// 发布或记录 `publishCredential` 对应的 iCloud Drive 同步系统集成状态。
    @discardableResult
    private func publishCredential(_ result: CredentialSyncResult) -> SyncStatus? {
        for url in result.downloadURLs {
            try? Self.requestDownloadIfNeeded(url)
        }
        if let record = result.winner?.record {
            credentialStateHandler(.record(record))
        } else if !result.downloadURLs.isEmpty {
            credentialStateHandler(.waitingForDownload)
        } else if !result.failures.isEmpty {
            credentialStateHandler(.failed)
        } else {
            credentialStateHandler(.noRecord)
        }

        if !result.downloadURLs.isEmpty {
            return .waitingForDownload
        }
        if !result.failures.isEmpty {
            return .failed
        }
        return nil
    }

    /// 发布或记录 `publishCredential` 对应的 iCloud Drive 同步系统集成状态。
    @discardableResult
    private func publishCredential(_ error: DriveSyncStoreError) -> SyncStatus {
        if case let .itemNotDownloaded(url) = error {
            try? Self.requestDownloadIfNeeded(url)
            credentialStateHandler(.waitingForDownload)
            return .waitingForDownload
        } else if case .missingProtocol = error {
            credentialStateHandler(.unavailable)
            return .folderUnavailable
        } else {
            credentialStateHandler(.failed)
            return .failed
        }
    }

    /// 在文件协调写入范围内执行传入操作，并返回协调后的结果。
    private func withCoordinatedWrite<Value>(
        at rootURL: URL,
        cancellation: SyncCycleCancellation = SyncCycleCancellation(),
        operation: (URL) throws -> Value
    ) throws -> Value {
        try cancellation.check()
        let didStartSecurityScope = rootURL.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope { rootURL.stopAccessingSecurityScopedResource() }
        }

        var coordinationError: NSError?
        var result: Result<Value, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: rootURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try cancellation.check()
                return try operation(coordinatedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    /// 执行 `requestDownloadIfNeeded` 对应的 iCloud Drive 同步系统集成输入输出操作。
    private static func requestDownloadIfNeeded(_ url: URL) throws {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// 结束 `finishSyncing` 对应的 iCloud Drive 同步系统集成流程，并释放或重置相关资源。
    private func finishSyncing() {
        lock.withLock {
            isSyncing = false
            needsAnotherCycle = false
        }
    }

    /// 延迟三十秒触发下一周期；令牌变化同时淘汰旧定时任务和旧周期 lease。
    private func schedulePeriodicSync(token: UInt64) {
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            let shouldRun = self.lock.withLock {
                self.configuration.isEnabled && self.configuration.scheduleToken == token
            }
            if shouldRun { self.syncNow() }
        }
    }

    /// 发布或记录 `publish` 对应的 iCloud Drive 同步系统集成状态。
    private func publish(_ error: Error, lease: CycleLease) {
        guard isCurrent(lease) else { return }
        if (error as NSError).domain == NSCocoaErrorDomain {
            statusHandler(.folderUnavailable)
        } else {
            statusHandler(.failed)
        }
    }

    /// 从启用且已配置的快照创建周期 lease。
    private func cycleLease(for configuration: Configuration) -> CycleLease? {
        guard configuration.isEnabled, let rootURL = configuration.rootURL else {
            return nil
        }
        return CycleLease(
            token: configuration.scheduleToken,
            rootURL: rootURL.standardizedFileURL
        )
    }

    /// 判断 lease 是否仍指向当前启用配置。
    private func isCurrent(_ lease: CycleLease) -> Bool {
        lock.withLock {
            configuration.isEnabled
                && configuration.scheduleToken == lease.token
                && configuration.rootURL?.standardizedFileURL == lease.rootURL
        }
    }

    /// 创建可传入 Core runner 和存储层的协作式取消检查。
    private func cancellation(for lease: CycleLease) -> SyncCycleCancellation {
        SyncCycleCancellation { [weak self] in
            guard let self else { return true }
            return !self.isCurrent(lease)
        }
    }
}

/// 扩展 `NSLock`，补充本文件所需的 iCloud Drive 同步系统集成能力。
private extension NSLock {
    /// 在锁保护范围内执行传入操作，并返回操作结果。
    func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try operation()
    }
}
