import Foundation
import MacToolsCore

final class ICloudDriveSyncCoordinator: @unchecked Sendable {
    typealias StatusHandler = @Sendable (SyncStatus) -> Void
    typealias RemoteSettingsHandler = @Sendable (AppSettings) -> Void
    typealias DevicesHandler = @Sendable ([SyncDeviceSummary]) -> Void

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

    private let localRepository: SyncLocalRepository
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let cycleRunner: DriveSyncCycleRunner
    private let statusHandler: StatusHandler
    private let remoteSettingsHandler: RemoteSettingsHandler
    private let devicesHandler: DevicesHandler
    private let queue = DispatchQueue(label: "com.mactools.icloud-drive-sync", qos: .utility)
    private let lock = NSLock()
    private var configuration: Configuration
    private var isSyncing = false
    private var needsAnotherCycle = false

    init(
        localRepository: SyncLocalRepository,
        deviceOverrideRepository: DeviceOverrideRepository,
        payloadStore: PayloadStore,
        historyLimit: Int,
        clipboardScope: ClipboardSyncScope,
        storageLimit: SyncStorageLimit,
        rootURL: URL?,
        statusHandler: @escaping StatusHandler,
        remoteSettingsHandler: @escaping RemoteSettingsHandler,
        devicesHandler: @escaping DevicesHandler
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
        self.statusHandler = statusHandler
        self.remoteSettingsHandler = remoteSettingsHandler
        self.devicesHandler = devicesHandler
        self.configuration = Configuration(
            rootURL: rootURL,
            historyLimit: historyLimit,
            clipboardScope: clipboardScope,
            storageLimit: storageLimit
        )
    }

    func setEnabled(_ enabled: Bool) {
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
        syncNow()
    }

    func updateConfiguration(
        historyLimit: Int,
        clipboardScope: ClipboardSyncScope,
        storageLimit: SyncStorageLimit
    ) {
        lock.withLock {
            configuration.historyLimit = historyLimit
            configuration.clipboardScope = clipboardScope
            configuration.storageLimit = storageLimit
        }
    }

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

    func resetSyncData() {
        let snapshot = lock.withLock { configuration }
        guard snapshot.isEnabled, let rootURL = snapshot.rootURL else { return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.withCoordinatedWrite(at: rootURL) { coordinatedRoot in
                    let store = DriveSyncStore(rootURL: coordinatedRoot)
                    let descriptor = try store.readProtocol()
                    try self.localRepository.bindStore(descriptor.storeID)
                    let generation = try self.localRepository.advanceGeneration(
                        storeID: descriptor.storeID
                    )
                    let deviceID = try self.deviceOverrideRepository.deviceID().uuidString
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
                self.syncNow()
            } catch {
                self.publish(error)
            }
        }
    }

    func removeDevice(_ removedDeviceID: String) {
        let snapshot = lock.withLock { configuration }
        guard snapshot.isEnabled, let rootURL = snapshot.rootURL else { return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.withCoordinatedWrite(at: rootURL) { coordinatedRoot in
                    let store = DriveSyncStore(rootURL: coordinatedRoot)
                    let descriptor = try store.readProtocol()
                    try self.localRepository.bindStore(descriptor.storeID)
                    let generation = try self.localRepository.currentGeneration(
                        storeID: descriptor.storeID
                    )
                    let removerDeviceID = try self.deviceOverrideRepository.deviceID().uuidString
                    guard removedDeviceID != removerDeviceID else { return }
                    try self.localRepository.preserveTombstones(
                        fromRemovedDeviceID: removedDeviceID,
                        generation: generation
                    )
                    try store.writeRemovedDevice(
                        SyncRemovedDeviceMarker(
                            removedDeviceID: removedDeviceID,
                            removerDeviceID: removerDeviceID,
                            generation: generation,
                            removedAt: Date()
                        )
                    )
                }
                self.syncNow()
            } catch {
                self.publish(error)
            }
        }
    }

    private func runCycles() {
        while true {
            let snapshot = lock.withLock { configuration }
            guard snapshot.isEnabled else {
                finishSyncing()
                return
            }
            guard let rootURL = snapshot.rootURL else {
                statusHandler(.unconfigured)
                finishSyncing()
                return
            }

            statusHandler(.syncing)
            do {
                let result = try withCoordinatedWrite(at: rootURL) { coordinatedRoot in
                    try cycleRunner.run(
                        rootURL: coordinatedRoot,
                        configuration: snapshot.cycleConfiguration
                    )
                }
                if let settings = result.remoteSettings {
                    remoteSettingsHandler(settings)
                }
                devicesHandler(result.devices)
                statusHandler(result.status)
            } catch let error as DriveSyncStoreError {
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
            } catch {
                publish(error)
            }

            let rerun = lock.withLock { () -> Bool in
                if needsAnotherCycle {
                    needsAnotherCycle = false
                    return true
                }
                isSyncing = false
                return false
            }
            if !rerun {
                schedulePeriodicSync(token: snapshot.scheduleToken)
                return
            }
        }
    }

    private func withCoordinatedWrite<Value>(
        at rootURL: URL,
        operation: (URL) throws -> Value
    ) throws -> Value {
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
            result = Result { try operation(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private static func requestDownloadIfNeeded(_ url: URL) throws {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private func finishSyncing() {
        lock.withLock {
            isSyncing = false
            needsAnotherCycle = false
        }
    }

    private func schedulePeriodicSync(token: UInt64) {
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            let shouldRun = self.lock.withLock {
                self.configuration.isEnabled && self.configuration.scheduleToken == token
            }
            if shouldRun { self.syncNow() }
        }
    }

    private func publish(_ error: Error) {
        if (error as NSError).domain == NSCocoaErrorDomain {
            statusHandler(.folderUnavailable)
        } else {
            statusHandler(.failed)
        }
    }
}

private extension NSLock {
    func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try operation()
    }
}
