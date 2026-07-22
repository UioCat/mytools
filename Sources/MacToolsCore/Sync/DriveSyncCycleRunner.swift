import Foundation

public struct DriveSyncCycleConfiguration: Sendable {
    public let historyLimit: Int
    public let clipboardScope: ClipboardSyncScope
    public let storageLimit: SyncStorageLimit

    public init(
        historyLimit: Int,
        clipboardScope: ClipboardSyncScope,
        storageLimit: SyncStorageLimit
    ) {
        self.historyLimit = historyLimit
        self.clipboardScope = clipboardScope
        self.storageLimit = storageLimit
    }
}

public struct DriveSyncCycleResult: Sendable {
    public let status: SyncStatus
    public let remoteSettings: AppSettings?
    public let devices: [SyncDeviceSummary]

    public init(
        status: SyncStatus,
        remoteSettings: AppSettings?,
        devices: [SyncDeviceSummary]
    ) {
        self.status = status
        self.remoteSettings = remoteSettings
        self.devices = devices
    }
}

public final class DriveSyncCycleRunner: @unchecked Sendable {
    public typealias DateProvider = @Sendable () -> Date
    public typealias DeviceNameProvider = @Sendable () -> String?
    public typealias DownloadRequester = @Sendable (URL) throws -> Void
    public typealias StoreFactory = @Sendable (URL) -> DriveSyncStore

    private let localRepository: SyncLocalRepository
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let payloadStore: PayloadStore
    private let currentDate: DateProvider
    private let deviceName: DeviceNameProvider
    private let requestDownload: DownloadRequester
    private let makeStore: StoreFactory

    public init(
        localRepository: SyncLocalRepository,
        deviceOverrideRepository: DeviceOverrideRepository,
        payloadStore: PayloadStore,
        currentDate: @escaping DateProvider = { Date() },
        deviceName: @escaping DeviceNameProvider,
        requestDownload: @escaping DownloadRequester,
        makeStore: @escaping StoreFactory = { DriveSyncStore(rootURL: $0) }
    ) {
        self.localRepository = localRepository
        self.deviceOverrideRepository = deviceOverrideRepository
        self.payloadStore = payloadStore
        self.currentDate = currentDate
        self.deviceName = deviceName
        self.requestDownload = requestDownload
        self.makeStore = makeStore
    }

    public func run(
        rootURL: URL,
        configuration: DriveSyncCycleConfiguration
    ) throws -> DriveSyncCycleResult {
        let now = currentDate()
        let currentDeviceName = deviceName()
        let store = makeStore(rootURL)
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
                try? requestDownload(url)
            }
        }
        var storageInventory = try store.storageInventory()
        let storedObjectsBeforeWrite = storageInventory.objects
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
        let receiptsByDeviceID = Dictionary(
            uniqueKeysWithValues: try localRepository.receipts().map { ($0.deviceID, $0) }
        )
        let peerReplicas = replicas.filter { $0.manifest.deviceID != deviceID }
        let alreadyAppliedPeerReplicas = peerReplicas.filter { replica in
            receiptsByDeviceID[replica.manifest.deviceID]?.matches(
                deviceID: replica.manifest.deviceID,
                generation: replica.manifest.generation,
                revision: replica.manifest.revision,
                manifestDigest: replica.manifestDigest
            ) == true
        }
        let alreadyAppliedDeviceIDs = Set(
            alreadyAppliedPeerReplicas.map(\.manifest.deviceID)
        )
        let unappliedPeerReplicas = peerReplicas.filter { replica in
            !alreadyAppliedDeviceIDs.contains(replica.manifest.deviceID)
        }
        for replica in alreadyAppliedPeerReplicas {
            seenRevisions[replica.manifest.deviceID] = max(
                seenRevisions[replica.manifest.deviceID] ?? 0,
                replica.manifest.revision
            )
        }

        var exportContentCache = SyncExportContentCache()
        var draft = try localRepository.exportBundle(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: configuration.clipboardScope,
            contentCache: &exportContentCache
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

        for replica in unappliedPeerReplicas {
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
                        try requestDownload(url)
                    } else {
                        hasInvalidRemoteContent = true
                    }
                }
            }
        }

        for replica in unappliedPeerReplicas {
            try localRepository.apply(tombstones: replica.tombstones)
        }
        let tombstonedRecordNames = try localRepository.tombstonedRecordNames(
            generation: generation
        )
        draft = try localRepository.exportBundle(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: configuration.clipboardScope,
            contentCache: &exportContentCache
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

        let currentUsage = storageInventory.usage(
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
        for replica in unappliedPeerReplicas {
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
            let finalBundle = draft.excludingContentIDs(
                excludedContentIDs.union(blockedImageContentIDs)
            )
            unavailableLocalRecordNames.formUnion(finalBundle.unavailableClipboardRecordNames)
            let manifest = try store.write(
                finalBundle,
                seenRevisions: seenRevisions,
                deviceName: currentDeviceName,
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
        if writtenBundle != nil {
            storageInventory = try store.storageInventory()
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
        let storedObjects = storageInventory.objects
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

        let finalStorageInventory = storageInventory.removingObjects(
            withContentIDs: removedGarbageIDs
        )
        let usage = finalStorageInventory.usage(
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
                    name: currentDeviceName ?? Self.fallbackDeviceName(deviceID),
                    isCurrentDevice: true,
                    lastUpdatedAt: writtenBundle == nil ? nil : now
                )
            )
        } else if writtenBundle != nil,
                  let index = devices.firstIndex(where: { $0.id == deviceID }) {
            devices[index].lastUpdatedAt = now
            devices[index].name = currentDeviceName ?? devices[index].name
        }
        devices.sort {
            if $0.isCurrentDevice != $1.isCurrentDevice { return $0.isCurrentDevice }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return DriveSyncCycleResult(
            status: status,
            remoteSettings: remoteSettings,
            devices: devices
        )
    }

    private static func fallbackDeviceName(_ deviceID: String) -> String {
        "Mac · \(deviceID.prefix(6))"
    }
}
