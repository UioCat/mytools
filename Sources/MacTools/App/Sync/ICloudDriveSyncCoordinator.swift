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
    }

    private struct CycleResult {
        var status: SyncStatus
        var remoteSettings: AppSettings?
        var devices: [SyncDeviceSummary]
    }

    private let localRepository: SyncLocalRepository
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let payloadStore: PayloadStore
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
        self.payloadStore = payloadStore
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
                    let generation = try self.localRepository.advanceGeneration(storeID: descriptor.storeID)
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
                    try performCycle(rootURL: coordinatedRoot, configuration: snapshot)
                }
                if let settings = result.remoteSettings {
                    remoteSettingsHandler(settings)
                }
                devicesHandler(result.devices)
                statusHandler(result.status)
            } catch let error as DriveSyncStoreError {
                if case let .itemNotDownloaded(url) = error {
                    try? requestDownloadIfNeeded(at: url)
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

    private func performCycle(
        rootURL: URL,
        configuration: Configuration
    ) throws -> CycleResult {
        let now = Date()
        let store = DriveSyncStore(rootURL: rootURL)
        let descriptor = try store.readProtocol()
        try localRepository.bindStore(descriptor.storeID)
        var resetReplicaState = false
        if try deviceOverrideRepository.storeID() != descriptor.storeID {
            try deviceOverrideRepository.setStoreID(descriptor.storeID)
            try deviceOverrideRepository.setReplicaRevision(0)
            try deviceOverrideRepository.setSeenRevisions([:])
            resetReplicaState = true
        }

        let remoteGeneration = try store.highestResetGeneration()
        if try localRepository.adoptGeneration(remoteGeneration, storeID: descriptor.storeID) {
            try deviceOverrideRepository.setReplicaRevision(0)
            try deviceOverrideRepository.setSeenRevisions([:])
            resetReplicaState = true
        }
        let generation = try localRepository.currentGeneration(storeID: descriptor.storeID)
        var deviceID = try deviceOverrideRepository.deviceID().uuidString
        let removedDeviceIDs = try store.removedDeviceIDs(generation: generation)
        if removedDeviceIDs.contains(deviceID) {
            try localRepository.prepareForReplacementDevice()
            deviceID = try deviceOverrideRepository.rotateDeviceID().uuidString
            resetReplicaState = true
        }

        let replicaScan = try store.scanReplicas(generation: generation)
        let replicas = replicaScan.replicas.filter {
            !removedDeviceIDs.contains($0.manifest.deviceID)
        }
        let replicaFailures = replicaScan.failures.filter {
            !removedDeviceIDs.contains($0.deviceID)
        }
        let ownReplicaUnverifiable = replicaFailures.contains { $0.deviceID == deviceID }
        let peerReplicaFailures = replicaFailures.filter { $0.deviceID != deviceID }
        for failure in peerReplicaFailures {
            if case let .itemNotDownloaded(url) = failure.error {
                try? requestDownloadIfNeeded(at: url)
            }
        }
        let storedObjectsBeforeWrite = try store.storedObjects()
        var storedBytesByContentID: [String: Int64] = [:]
        for object in storedObjectsBeforeWrite {
            storedBytesByContentID[object.contentID] = max(
                storedBytesByContentID[object.contentID] ?? 0,
                object.byteCount
            )
        }
        let storedContentIDs = Set(storedBytesByContentID.keys)

        let persistedRevision = try deviceOverrideRepository.replicaRevision()
        let ownStoredRevision = replicas.first {
            $0.manifest.deviceID == deviceID
        }?.manifest.revision ?? 0
        let currentRevision = max(persistedRevision, ownStoredRevision)
        let nextRevision = currentRevision + 1
        let persistedSeenRevisions = try deviceOverrideRepository.seenRevisions()
        var seenRevisions = persistedSeenRevisions.filter {
            !removedDeviceIDs.contains($0.key)
        }
        if let ownReplica = replicas.first(where: { $0.manifest.deviceID == deviceID }) {
            for (seenDeviceID, revision) in ownReplica.manifest.seenRevisions
                where !removedDeviceIDs.contains(seenDeviceID) {
                seenRevisions[seenDeviceID] = max(seenRevisions[seenDeviceID] ?? 0, revision)
            }
            seenRevisions[deviceID] = max(
                seenRevisions[deviceID] ?? 0,
                ownReplica.manifest.revision
            )
        }

        var draft = try localRepository.exportBundle(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: configuration.clipboardScope
        )
        var contentByID = Dictionary(uniqueKeysWithValues: draft.contents.map { ($0.contentID, $0.data) })
        var missingRemoteContent = peerReplicaFailures.contains {
            if case .itemNotDownloaded = $0.error { return true }
            return false
        }
        let hasInvalidPeerReplica = peerReplicaFailures.contains {
            if case .itemNotDownloaded = $0.error { return false }
            return true
        }
        var hasInvalidRemoteContent = false
        var incompleteDeviceIDs: Set<String> = []

        for replica in replicas {
            guard replica.manifest.deviceID != deviceID else { continue }
            for record in replica.clipboard.records where contentByID[record.contentID] == nil {
                do {
                    if let data = try store.contentData(contentID: record.contentID, kind: record.kind) {
                        contentByID[record.contentID] = data
                    } else {
                        hasInvalidRemoteContent = true
                        incompleteDeviceIDs.insert(replica.manifest.deviceID)
                    }
                } catch let error as DriveSyncStoreError {
                    incompleteDeviceIDs.insert(replica.manifest.deviceID)
                    if case let .itemNotDownloaded(url) = error {
                        missingRemoteContent = true
                        try requestDownloadIfNeeded(at: url)
                    } else {
                        hasInvalidRemoteContent = true
                    }
                }
            }
        }

        for replica in replicas where replica.manifest.deviceID != deviceID {
            try localRepository.apply(tombstones: replica.tombstones)
        }
        let tombstonedRecordNames = try localRepository.tombstonedRecordNames(
            generation: generation
        )
        draft = try localRepository.exportBundle(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: configuration.clipboardScope
        )
        var unavailableLocalRecordNames = draft.unavailableClipboardRecordNames
        var allRecords = draft.clipboard.records
        for replica in replicas where replica.manifest.deviceID != deviceID {
            allRecords.append(contentsOf: replica.clipboard.records.filter {
                !tombstonedRecordNames.contains($0.recordName)
            })
        }

        var candidates = allRecords.map { record in
            SyncRetentionCandidate(
                contentID: record.contentID,
                kind: record.kind,
                byteCount: Int64(contentByID[record.contentID]?.count ?? 0) > 0
                    ? Int64(contentByID[record.contentID]?.count ?? 0)
                    : storedBytesByContentID[record.contentID] ?? 0,
                createdAt: record.createdAt,
                retentionAt: record.retentionAt,
                isFavorite: record.isFavorite,
                isPinned: record.isPinned,
                favoriteClock: record.favoriteClock,
                pinnedClock: record.pinnedClock
            )
        }
        var mergedCandidates: [String: SyncRetentionCandidate] = [:]
        for candidate in candidates {
            mergedCandidates[candidate.contentID] = mergedCandidates[candidate.contentID]?.merging(candidate)
                ?? candidate
        }
        let remoteEvictions = try store.evictions(generation: generation).filter {
            !removedDeviceIDs.contains($0.deviceID)
        }
        let effectiveRemoteEvictions = remoteEvictions.filter { eviction in
            guard let candidate = mergedCandidates[eviction.contentID],
                  eviction.isEffective(for: candidate) else { return false }
            return true
        }
        let effectiveRemoteEvictionIDs = Set(effectiveRemoteEvictions.map(\.contentID))
        candidates.removeAll { effectiveRemoteEvictionIDs.contains($0.contentID) }

        let currentUsage = try store.usage(
            capacityBytes: configuration.storageLimit.byteLimit,
            ordinaryHistoryCount: 0
        )
        let candidateContentIDs = Set(candidates.map(\.contentID))
        let unreferencedStoredBytes = storedObjectsBeforeWrite.lazy
            .filter { !candidateContentIDs.contains($0.contentID) }
            .reduce(Int64(0)) { $0 + $1.byteCount }
        let projectedSnapshotBytes = Int64(
            try SyncSnapshotCodec.encode(draft.clipboard).count
                + SyncSnapshotCodec.encode(draft.preferences).count
                + SyncSnapshotCodec.encode(draft.tombstones).count
                + 4_096
        )
        let decision = SyncRetentionPolicy.decide(
            candidates: candidates,
            metadataBytes: currentUsage.metadataBytes
                + unreferencedStoredBytes
                + projectedSnapshotBytes,
            capacityLimitBytes: configuration.storageLimit.byteLimit,
            generation: generation,
            deviceID: deviceID,
            now: now
        )
        let excludedContentIDs = effectiveRemoteEvictionIDs.union(
            Set(decision.evictions.map(\.contentID))
        )
        let newObjectBytes = draft.contents.lazy
            .filter {
                decision.keptContentIDs.contains($0.contentID)
                    && !excludedContentIDs.contains($0.contentID)
                    && !storedContentIDs.contains($0.contentID)
            }
            .reduce(Int64(0)) { $0 + Int64($1.data.count) }
        let shouldPauseImageUploads = SyncRetentionPolicy.mustPauseImageUploads(
            decision: decision,
            currentUsedBytes: currentUsage.usedBytes,
            newObjectBytes: newObjectBytes,
            projectedMetadataBytes: projectedSnapshotBytes,
            capacityLimitBytes: configuration.storageLimit.byteLimit
        )
        let blockedImageContentIDs: Set<String>
        if shouldPauseImageUploads {
            blockedImageContentIDs = Set(mergedCandidates.values.compactMap { candidate in
                candidate.kind == .imageData
                    && decision.keptContentIDs.contains(candidate.contentID)
                    && !excludedContentIDs.contains(candidate.contentID)
                    && !storedContentIDs.contains(candidate.contentID)
                    ? candidate.contentID
                    : nil
            })
        } else {
            blockedImageContentIDs = []
        }
        let blockedClipboardRecordNames = Set(draft.clipboard.records.compactMap { record in
            blockedImageContentIDs.contains(record.contentID) ? record.recordName : nil
        })
        let deferredClipboardRecordNames = blockedClipboardRecordNames.union(
            unavailableLocalRecordNames
        )

        var remoteSettings: AppSettings?
        for replica in replicas where replica.manifest.deviceID != deviceID {
            let filtered = SyncClipboardSnapshot(
                deviceID: replica.clipboard.deviceID,
                generation: replica.clipboard.generation,
                revision: replica.clipboard.revision,
                records: replica.clipboard.records.filter {
                    !tombstonedRecordNames.contains($0.recordName)
                        && decision.keptContentIDs.contains($0.contentID)
                        && !excludedContentIDs.contains($0.contentID)
                }
            )
            try localRepository.apply(
                clipboard: filtered,
                contents: contentByID,
                payloadStore: payloadStore,
                historyLimit: configuration.historyLimit
            )
            remoteSettings = try localRepository.apply(preferences: replica.preferences) ?? remoteSettings
            if !incompleteDeviceIDs.contains(replica.manifest.deviceID) {
                seenRevisions[replica.manifest.deviceID] = max(
                    seenRevisions[replica.manifest.deviceID] ?? 0,
                    replica.manifest.revision
                )
                try localRepository.recordReceipt(
                    SyncReplicaReceipt(
                        deviceID: replica.manifest.deviceID,
                        generation: generation,
                        revision: replica.manifest.revision,
                        manifestDigest: replica.manifestDigest,
                        appliedAt: now
                    )
                )
            }
        }

        let compactedTombstones: Set<String> = replicaFailures.isEmpty
            ? try localRepository.compactAcknowledgedTombstones(
                activeManifests: replicas.map(\.manifest),
                localDeviceID: deviceID,
                generation: generation
            )
            : []

        var localEvictionsByContentID: [String: SyncEvictionRecord] = [:]
        for eviction in effectiveRemoteEvictions where eviction.deviceID == deviceID {
            localEvictionsByContentID[eviction.contentID] = eviction
        }
        for eviction in decision.evictions {
            localEvictionsByContentID[eviction.contentID] = eviction
        }
        let localEvictions = localEvictionsByContentID.values.sorted {
            $0.contentID < $1.contentID
        }
        let currentEvictionSnapshot = try store.evictionSnapshot(deviceID: deviceID)
        let evictionSnapshotChanged = currentEvictionSnapshot?.generation != generation
            || currentEvictionSnapshot?.records != localEvictions
        let hasRelevantPendingChanges = try localRepository.hasPendingChanges(
            excludingClipboardRecordNames: deferredClipboardRecordNames
        )
        let needsWrite = resetReplicaState
            || currentRevision == 0
            || ownReplicaUnverifiable
            || hasRelevantPendingChanges
            || seenRevisions != persistedSeenRevisions
            || !compactedTombstones.isEmpty
            || evictionSnapshotChanged

        var writtenBundle: SyncExportBundle?
        if needsWrite {
            seenRevisions[deviceID] = nextRevision
            let finalBundle = try localRepository.exportBundle(
                deviceID: deviceID,
                generation: generation,
                revision: nextRevision,
                scope: configuration.clipboardScope,
                excludingContentIDs: excludedContentIDs.union(blockedImageContentIDs)
            )
            unavailableLocalRecordNames.formUnion(finalBundle.unavailableClipboardRecordNames)
            let manifest = try store.write(
                finalBundle,
                seenRevisions: seenRevisions,
                deviceName: Host.current().localizedName,
                updatedAt: now
            )
            if evictionSnapshotChanged {
                try store.writeEvictions(
                    SyncEvictionSnapshot(
                        deviceID: deviceID,
                        generation: generation,
                        records: localEvictions
                    )
                )
            }
            try localRepository.acknowledgeSnapshot(
                upTo: finalBundle.outboxCutoff,
                excludingClipboardRecordNames: blockedClipboardRecordNames.union(
                    unavailableLocalRecordNames
                ),
                uploadedContentIDs: Set(finalBundle.contents.map(\.contentID))
            )
            try deviceOverrideRepository.setReplicaRevision(manifest.revision)
            try deviceOverrideRepository.setSeenRevisions(seenRevisions)
            writtenBundle = finalBundle
        }

        var referencedContentIDs: Set<String> = []
        for replica in replicas where writtenBundle == nil || replica.manifest.deviceID != deviceID {
            referencedContentIDs.formUnion(replica.clipboard.records.compactMap { record in
                excludedContentIDs.contains(record.contentID) ? nil : record.contentID
            })
        }
        if let writtenBundle {
            referencedContentIDs.formUnion(writtenBundle.clipboard.records.map(\.contentID))
        }
        let storedObjects = try store.storedObjects()
        var removedGarbageIDs: Set<String> = []
        if replicaFailures.isEmpty {
            let garbageIDs = try localRepository.garbageCollectionCandidates(
                allContentIDs: Set(storedObjects.map(\.contentID)),
                referencedContentIDs: referencedContentIDs
            )
            for object in storedObjects where garbageIDs.contains(object.contentID) {
                try store.removeObject(object)
                removedGarbageIDs.insert(object.contentID)
            }
        }
        try localRepository.acknowledgeGarbageCollected(contentIDs: removedGarbageIDs)

        let usage = try store.usage(
            capacityBytes: configuration.storageLimit.byteLimit,
            ordinaryHistoryCount: decision.ordinaryCount
        )
        let status: SyncStatus
        if missingRemoteContent {
            status = .waitingForDownload
        } else if hasInvalidPeerReplica
                    || hasInvalidRemoteContent
                    || !unavailableLocalRecordNames.isEmpty {
            status = .failed
        } else if shouldPauseImageUploads || usage.usedBytes > usage.capacityBytes {
            status = .capacityFull(usage: usage)
        } else {
            status = .synced(lastSyncAt: now, usage: usage)
        }
        var devices = replicas.map { replica in
            SyncDeviceSummary(
                id: replica.manifest.deviceID,
                name: replica.manifest.deviceName ?? Self.fallbackDeviceName(replica.manifest.deviceID),
                isCurrentDevice: replica.manifest.deviceID == deviceID,
                lastUpdatedAt: replica.manifest.updatedAt
            )
        }
        if !devices.contains(where: { $0.id == deviceID }) {
            devices.append(
                SyncDeviceSummary(
                    id: deviceID,
                    name: Host.current().localizedName ?? Self.fallbackDeviceName(deviceID),
                    isCurrentDevice: true,
                    lastUpdatedAt: writtenBundle == nil ? nil : now
                )
            )
        } else if writtenBundle != nil,
                  let index = devices.firstIndex(where: { $0.id == deviceID }) {
            devices[index].lastUpdatedAt = now
            devices[index].name = Host.current().localizedName ?? devices[index].name
        }
        devices.sort {
            if $0.isCurrentDevice != $1.isCurrentDevice { return $0.isCurrentDevice }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return CycleResult(status: status, remoteSettings: remoteSettings, devices: devices)
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

    private func requestDownloadIfNeeded(at url: URL) throws {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    private static func fallbackDeviceName(_ deviceID: String) -> String {
        "Mac · \(deviceID.prefix(6))"
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
