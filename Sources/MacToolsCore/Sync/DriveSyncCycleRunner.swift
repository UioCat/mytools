// `DriveSyncCycleRunner` 的同步核心领域实现。
// 负责协议模型、合并、对象存储和凭据对账，不管理 AppKit 生命周期。

import Foundation

/// manifest 协调区间发现更高本机 revision 时，当前草稿不得确认，调度器应立即重跑。
public enum DriveSyncCycleRetryError: Error, Equatable, Sendable {
    case newerRemoteReplica
}

/// 封装 `DriveSyncCycleConfiguration` 在同步核心领域中的值语义和相关操作。
public struct DriveSyncCycleConfiguration: Sendable {
    public let historyLimit: Int
    public let clipboardScope: ClipboardSyncScope
    public let storageLimit: SyncStorageLimit

    /// 创建 `DriveSyncCycleConfiguration`，保存传入依赖并建立初始状态。
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

/// 封装 `DriveSyncCycleResult` 在同步核心领域中的值语义和相关操作。
public struct DriveSyncCycleResult: Sendable {
    public let status: SyncStatus
    public let remoteSettings: AppSettings?
    public let devices: [SyncDeviceSummary]

    /// 创建 `DriveSyncCycleResult`，保存传入依赖并建立初始状态。
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

/// 管理 `DriveSyncCycleRunner` 在同步核心领域中的生命周期、依赖和可变状态。
public final class DriveSyncCycleRunner: @unchecked Sendable {
    /// 同步内容缓存使用的复合键；摘要相同但类型不同的对象不能共享缓存条目。
    private struct ContentKey: Hashable {
        var contentID: String
        var kind: ClipboardContentKind

        /// 内容摘要和载荷类型共同确定缓存项身份，避免不同目录类型错误复用。
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.contentID == rhs.contentID && lhs.kind == rhs.kind
        }

        /// 使用与相等判断相同的字段生成哈希，保持 Hashable 约定。
        func hash(into hasher: inout Hasher) {
            hasher.combine(contentID)
            hasher.combine(kind.rawValue)
        }
    }

    /// 保存一次稳定远端观察结果，供无变化周期跳过重复目录扫描和摘要计算。
    private struct ObservationCache {
        var rootURL: URL
        var storeID: UUID
        var generation: Int
        var replicasByDeviceID: [String: DriveSyncReplica]
        var replicaDigests: [String: String]
        var removedDeviceIDs: Set<String>
        var inventory: SyncStorageInventory
        var lastFullInventoryAuditAt: Date
    }

    /// 为同步核心领域中的相关类型提供 `DateProvider` 别名。
    public typealias DateProvider = @Sendable () -> Date
    /// 为同步核心领域中的相关类型提供 `DeviceNameProvider` 别名。
    public typealias DeviceNameProvider = @Sendable () -> String?
    /// 为同步核心领域中的相关类型提供 `DownloadRequester` 别名。
    public typealias DownloadRequester = @Sendable (URL) throws -> Void
    /// 为同步核心领域中的相关类型提供 `StoreFactory` 别名。
    public typealias StoreFactory = @Sendable (URL) -> DriveSyncStore

    private let localRepository: SyncLocalRepository
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let payloadStore: PayloadStore
    private let currentDate: DateProvider
    private let deviceName: DeviceNameProvider
    private let requestDownload: DownloadRequester
    private let makeStore: StoreFactory
    private let inventoryAuditInterval: TimeInterval
    private let observationLock = NSLock()
    private var observationCache: ObservationCache?

    /// 创建 `DriveSyncCycleRunner`，保存传入依赖并建立初始状态。
    public init(
        localRepository: SyncLocalRepository,
        deviceOverrideRepository: DeviceOverrideRepository,
        payloadStore: PayloadStore,
        currentDate: @escaping DateProvider = { Date() },
        deviceName: @escaping DeviceNameProvider,
        requestDownload: @escaping DownloadRequester,
        makeStore: @escaping StoreFactory = { DriveSyncStore(rootURL: $0) },
        inventoryAuditInterval: TimeInterval = 5 * 60
    ) {
        self.localRepository = localRepository
        self.deviceOverrideRepository = deviceOverrideRepository
        self.payloadStore = payloadStore
        self.currentDate = currentDate
        self.deviceName = deviceName
        self.requestDownload = requestDownload
        self.makeStore = makeStore
        self.inventoryAuditInterval = max(0, inventoryAuditInterval)
    }

    /// 主动失效观察缓存；目录清理或协调器外部写入后，下轮会完整重建。
    public func invalidateObservationCache() {
        observationLock.withLock {
            observationCache = nil
        }
    }

    /// 执行一次完整同步：采纳代际、读取副本、应用墓碑、容量裁剪、写回并确认 receipt。
    public func run(
        rootURL: URL,
        configuration: DriveSyncCycleConfiguration,
        cancellation: SyncCycleCancellation = SyncCycleCancellation(),
        forceWrite: Bool = false
    ) throws -> DriveSyncCycleResult {
        try cancellation.check()
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

        // reset generation 高于本地时必须先清空旧副本进度，避免旧代际数据重新出现。
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

        let cachedObservation = cachedObservation(
            rootURL: rootURL,
            storeID: descriptor.storeID,
            generation: generation
        )
        let replicaScan = try store.scanReplicas(
            generation: generation,
            cachedReplicasByDeviceID: cachedObservation?.replicasByDeviceID ?? [:],
            ownedDeviceID: deviceID
        )
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
        let replicaDigests = Dictionary(
            uniqueKeysWithValues: replicas.map {
                ($0.manifest.deviceID, $0.manifestDigest)
            }
        )
        let cachedInventoryIsFresh: Bool
        if let cachedObservation {
            let auditAge = now.timeIntervalSince(
                cachedObservation.lastFullInventoryAuditAt
            )
            cachedInventoryIsFresh = cachedObservation.replicaDigests == replicaDigests
                && cachedObservation.removedDeviceIDs == removedDeviceIDs
                && auditAge >= 0
                && auditAge < inventoryAuditInterval
        } else {
            cachedInventoryIsFresh = false
        }
        let lastFullInventoryAuditAt: Date
        var storageInventory: SyncStorageInventory
        if cachedInventoryIsFresh, let cachedObservation {
            storageInventory = cachedObservation.inventory
            lastFullInventoryAuditAt = cachedObservation.lastFullInventoryAuditAt
        } else {
            storageInventory = try store.storageInventory()
            lastFullInventoryAuditAt = now
        }
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
        // receipt 同时绑定设备、代际、revision 和 manifest 摘要，完全匹配才可跳过重复应用。
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

        var draft = try localRepository.exportDraft(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: configuration.clipboardScope
        )
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

        try cancellation.check()
        for replica in unappliedPeerReplicas {
            try localRepository.apply(tombstones: replica.tombstones)
        }
        let tombstonedRecordNames = try localRepository.tombstonedRecordNames(
            generation: generation
        )
        draft = try localRepository.exportDraft(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: configuration.clipboardScope
        )
        let localDescriptorsByKey = Dictionary(
            uniqueKeysWithValues: draft.contentDescriptors.map {
                (
                    ContentKey(contentID: $0.contentID, kind: $0.kind),
                    $0
                )
            }
        )
        var unavailableLocalRecordNames = draft.unavailableClipboardRecordNames
        var allRecords = draft.clipboard.records
        for replica in replicas where replica.manifest.deviceID != deviceID {
            allRecords.append(contentsOf: replica.clipboard.records.filter {
                !tombstonedRecordNames.contains($0.recordName)
            })
        }

        var candidates: [SyncRetentionCandidate] = []
        var unknownContentIDs: Set<String> = []
        for record in allRecords {
            let key = ContentKey(contentID: record.contentID, kind: record.kind)
            guard let byteCount = localDescriptorsByKey[key]?.storedByteCount
                    ?? storedBytesByContentID[record.contentID] else {
                unknownContentIDs.insert(record.contentID)
                hasInvalidRemoteContent = true
                continue
            }
            candidates.append(SyncRetentionCandidate(
                contentID: record.contentID,
                kind: record.kind,
                byteCount: byteCount,
                createdAt: record.createdAt,
                retentionAt: record.retentionAt,
                isFavorite: record.isFavorite,
                isPinned: record.isPinned,
                favoriteClock: record.favoriteClock,
                pinnedClock: record.pinnedClock
            ))
        }
        for replica in unappliedPeerReplicas where replica.clipboard.records.contains(
            where: { unknownContentIDs.contains($0.contentID) }
        ) {
            incompleteDeviceIDs.insert(replica.manifest.deviceID)
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
        let newObjectBytes = draft.contentDescriptors.lazy
            .filter {
                decision.keptContentIDs.contains($0.contentID)
                    && !excludedContentIDs.contains($0.contentID)
                    && !storedContentIDs.contains($0.contentID)
            }
            .reduce(Int64(0)) { $0 + $1.storedByteCount }
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
        try cancellation.check()
        for replica in unappliedPeerReplicas {
            try cancellation.check()
            let filteredRecords = replica.clipboard.records.filter {
                    !tombstonedRecordNames.contains($0.recordName)
                        && decision.keptContentIDs.contains($0.contentID)
                        && !excludedContentIDs.contains($0.contentID)
                        && !unknownContentIDs.contains($0.contentID)
                }
            let recordsByContent = Dictionary(grouping: filteredRecords) {
                ContentKey(contentID: $0.contentID, kind: $0.kind)
            }
            for (key, records) in recordsByContent.sorted(by: {
                if $0.key.contentID != $1.key.contentID {
                    return $0.key.contentID < $1.key.contentID
                }
                return $0.key.kind.rawValue < $1.key.kind.rawValue
            }) {
                try cancellation.check()
                var contentData: Data?
                var sharedContentError: DriveSyncStoreError?
                do {
                    contentData = try store.contentData(
                        contentID: key.contentID,
                        kind: key.kind
                    )
                } catch let error as DriveSyncStoreError {
                    sharedContentError = error
                } catch {
                    sharedContentError = .unreadableContent(key.contentID)
                }

                if contentData == nil,
                   let descriptor = localDescriptorsByKey[key] {
                    contentData = try? localRepository.materializeContent(descriptor).data
                }
                guard let contentData else {
                    incompleteDeviceIDs.insert(replica.manifest.deviceID)
                    if case let .itemNotDownloaded(url) = sharedContentError {
                        missingRemoteContent = true
                        try requestDownload(url)
                    } else {
                        hasInvalidRemoteContent = true
                    }
                    continue
                }

                try localRepository.apply(
                    clipboard: SyncClipboardSnapshot(
                        deviceID: replica.clipboard.deviceID,
                        generation: replica.clipboard.generation,
                        revision: replica.clipboard.revision,
                        records: records
                    ),
                    contents: [key.contentID: contentData],
                    payloadStore: payloadStore,
                    historyLimit: configuration.historyLimit
                )
            }
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
            || forceWrite
            || hasRelevantPendingChanges
            || seenRevisions != persistedSeenRevisions
            || !compactedTombstones.isEmpty
            || evictionSnapshotChanged

        var writtenBundle: SyncExportBundle?
        var writtenManifestDigest: String?
        var writtenReplica: DriveSyncReplica?
        if needsWrite {
            // 从这里开始会改变目录；任一步失败都让下轮回退为完整 inventory 审计。
            invalidateObservationCache()
            try cancellation.check()
            seenRevisions[deviceID] = nextRevision
            let preparedDraft = draft.excludingContentIDs(
                excludedContentIDs.union(blockedImageContentIDs)
            )
            let preparation = try store.prepareContents(
                preparedDraft.contentDescriptors,
                cancellation: cancellation
            ) { descriptor in
                try? self.localRepository.materializeContent(descriptor)
            }
            unavailableLocalRecordNames.formUnion(
                preparedDraft.clipboard.records.compactMap { record in
                    preparation.unavailableContentIDs.contains(record.contentID)
                        ? record.recordName
                        : nil
                }
            )
            let finalDraft = preparedDraft.excludingContentIDs(
                preparation.unavailableContentIDs
            )
            let finalBundle = finalDraft.bundle()
            storageInventory = storageInventory.applyingPreparedContents(
                preparedDraft.contentDescriptors,
                uploadedContentIDs: preparation.uploadedContentIDs
            )
            let writeResult = try store.writeWithMetadataDelta(
                finalBundle,
                seenRevisions: seenRevisions,
                deviceName: currentDeviceName,
                updatedAt: now,
                cancellation: cancellation
            )
            if writeResult.outcome == .adoptedNewerRemote {
                try deviceOverrideRepository.setReplicaRevision(writeResult.manifest.revision)
                try deviceOverrideRepository.setSeenRevisions(writeResult.manifest.seenRevisions)
                invalidateObservationCache()
                throw DriveSyncCycleRetryError.newerRemoteReplica
            }
            storageInventory = storageInventory.adjustingMetadataBytes(
                by: writeResult.metadataByteDelta
            )
            if evictionSnapshotChanged {
                try cancellation.check()
                let evictionMetadataDelta = try store.writeEvictions(
                    SyncEvictionSnapshot(
                        deviceID: deviceID,
                        generation: generation,
                        records: localEvictions
                    )
                )
                storageInventory = storageInventory.adjustingMetadataBytes(
                    by: evictionMetadataDelta
                )
            }
            try cancellation.check()
            let excludedRecordNames = blockedClipboardRecordNames.union(
                unavailableLocalRecordNames
            )
            let acknowledgedContentIDs = preparation.availableContentIDs.intersection(
                Set(finalDraft.contentDescriptors.map(\.contentID))
            )
            if let publicationIdentity = writeResult.publicationIdentity {
                try localRepository.acknowledgePublishedSnapshot(
                    upTo: finalBundle.outboxCutoff,
                    excludingClipboardRecordNames: excludedRecordNames,
                    uploadedContentIDs: acknowledgedContentIDs,
                    publicationIdentity: publicationIdentity,
                    manifestDigest: writeResult.manifestDigest,
                    revision: writeResult.manifest.revision,
                    seenRevisions: seenRevisions,
                    at: now
                )
                try? store.cleanupSnapshotPublications(
                    storeID: publicationIdentity.storeID,
                    deviceID: publicationIdentity.deviceID,
                    generation: publicationIdentity.generation,
                    protectedDirectories: Set(
                        [writeResult.manifest.snapshotDirectory].compactMap { $0 }
                    )
                )
            } else {
                try localRepository.acknowledgeSnapshot(
                    upTo: finalBundle.outboxCutoff,
                    excludingClipboardRecordNames: excludedRecordNames,
                    uploadedContentIDs: acknowledgedContentIDs
                )
                try deviceOverrideRepository.setReplicaRevision(writeResult.manifest.revision)
                try deviceOverrideRepository.setSeenRevisions(seenRevisions)
            }
            writtenBundle = finalBundle
            writtenManifestDigest = writeResult.manifestDigest
            writtenReplica = DriveSyncReplica(
                manifest: writeResult.manifest,
                clipboard: finalBundle.clipboard,
                preferences: finalBundle.preferences,
                tombstones: finalBundle.tombstones,
                manifestDigest: writeResult.manifestDigest
            )
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
            if !garbageIDs.isEmpty {
                invalidateObservationCache()
            }
            for object in storedObjects where garbageIDs.contains(object.contentID) {
                try cancellation.check()
                try store.removeObject(object)
                removedGarbageIDs.insert(object.contentID)
            }
        }
        try localRepository.acknowledgeGarbageCollected(contentIDs: removedGarbageIDs)

        let finalStorageInventory = storageInventory.removingObjects(
            withContentIDs: removedGarbageIDs
        )
        var reusableReplicasByDeviceID = Dictionary(
            uniqueKeysWithValues: replicas.map {
                ($0.manifest.deviceID, $0)
            }
        )
        var resultingReplicaDigests = replicaDigests
        if let writtenManifestDigest, let writtenReplica {
            reusableReplicasByDeviceID[deviceID] = writtenReplica
            resultingReplicaDigests[deviceID] = writtenManifestDigest
        }
        storeObservation(
            ObservationCache(
                rootURL: rootURL.standardizedFileURL,
                storeID: descriptor.storeID,
                generation: generation,
                replicasByDeviceID: reusableReplicasByDeviceID,
                replicaDigests: resultingReplicaDigests,
                removedDeviceIDs: removedDeviceIDs,
                inventory: finalStorageInventory,
                lastFullInventoryAuditAt: lastFullInventoryAuditAt
            )
        )
        let usage = finalStorageInventory.usage(
            capacityBytes: configuration.storageLimit.byteLimit,
            ordinaryHistoryCount: decision.ordinaryCount
        )
        let status: SyncStatus
        if missingRemoteContent {
            status = .waitingForDownload
        } else if replicaFailures.contains(where: {
            if case .fileConflict = $0.error { return true }
            return false
        }) {
            status = .conflictNeedsAttention
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

    /// 只返回与当前目录、store 和 generation 完全匹配的观察缓存。
    private func cachedObservation(
        rootURL: URL,
        storeID: UUID,
        generation: Int
    ) -> ObservationCache? {
        observationLock.withLock {
            guard let observationCache,
                  observationCache.rootURL == rootURL.standardizedFileURL,
                  observationCache.storeID == storeID,
                  observationCache.generation == generation else {
                return nil
            }
            return observationCache
        }
    }

    /// 原子替换观察缓存；缓存丢失只会让下轮回退到完整扫描。
    private func storeObservation(_ observation: ObservationCache) {
        observationLock.withLock {
            observationCache = observation
        }
    }

    /// 计算并返回 `fallbackDeviceName` 对应的同步核心领域数据或状态结果。
    private static func fallbackDeviceName(_ deviceID: String) -> String {
        "Mac · \(deviceID.prefix(6))"
    }
}
