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
    // 仅为旧调用方保留的参数；导出固定收藏范围，storageLimit 不再参与容量决策。
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

    private struct LegacyCleanupProgress {
        var revision: Int64
        var manifestDigest: String
        var lastScannedDirectory: String?
        var nextAuditAt: Date?
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
        var needsContentRefresh: Bool
        var legacyCleanupProgress: LegacyCleanupProgress?
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
    private let revisionInventoryCache = SyncRevisionInventoryCache()

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

    /// 执行一次完整同步：采纳代际、合并收藏和取消证据、应用墓碑、写回并确认 receipt。
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
        let descriptor = try store.requireFavoritesOnlyProtocol(cancellation: cancellation)
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
            if cachedObservation.needsContentRefresh {
                let contents = try store.contentInventory(cancellation: cancellation)
                storageInventory = SyncStorageInventory(
                    objects: contents.objects, imageBytes: contents.imageBytes,
                    textBytes: contents.textBytes, metadataBytes: storageInventory.metadataBytes
                )
            }
            lastFullInventoryAuditAt = cachedObservation.lastFullInventoryAuditAt
        } else {
            storageInventory = try store.storageInventory(
                revisionCache: revisionInventoryCache, cancellation: cancellation
            )
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
        // 移除设备只改变参与者集合，不能抹去已发布的因果历史，否则后续向量会回退。
        var seenRevisions = persistedSeenRevisions
        if let ownReplica = replicas.first(where: { $0.manifest.deviceID == deviceID }) {
            for (seenDeviceID, revision) in ownReplica.manifest.seenRevisions {
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
        // 本机数据库恢复备份后，云端自己的较新快照也必须先导入，不能只追平 revision。
        let peerReplicas = replicas.filter {
            $0.manifest.deviceID != deviceID || $0.manifest.revision > persistedRevision
        }
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
            let legacyRemovals = replica.clipboard.records.compactMap { record in
                !record.isFavorite && record.favoriteClock.counter > 0
                    ? SyncFavoriteRemoval(contentID: record.contentID, favoriteClock: record.favoriteClock)
                    : nil
            }
            try localRepository.applyFavoriteRemovals(
                replica.clipboard.favoriteRemovals + legacyRemovals, generation: generation,
                historyLimit: configuration.historyLimit
            )
        }
        let removalsByContentID = Dictionary(uniqueKeysWithValues: try localRepository.favoriteRemovals(
            generation: generation
        ).map { ($0.contentID, $0) })
        let tombstonedRecordNames = try localRepository.tombstonedRecordNames(
            generation: generation
        )
        var draft = try localRepository.exportDraft(
            deviceID: deviceID,
            generation: generation,
            revision: nextRevision,
            scope: .favoritesOnly
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
        for replica in peerReplicas {
            allRecords.append(contentsOf: replica.clipboard.records.filter {
                $0.isFavorite && !tombstonedRecordNames.contains($0.recordName)
                    && removalsByContentID[$0.contentID]?.excludes($0) != true
            })
        }

        var unknownContentIDs: Set<String> = []
        for record in allRecords {
            let key = ContentKey(contentID: record.contentID, kind: record.kind)
            if localDescriptorsByKey[key] == nil && storedBytesByContentID[record.contentID] == nil {
                unknownContentIDs.insert(record.contentID)
                missingRemoteContent = true
                try? requestDownload(store.contentLocation(contentID: record.contentID, kind: record.kind))
            }
        }
        for replica in unappliedPeerReplicas where replica.clipboard.records.contains(
            where: { $0.isFavorite && unknownContentIDs.contains($0.contentID) }
        ) {
            incompleteDeviceIDs.insert(replica.manifest.deviceID)
        }

        var remoteSettings: AppSettings?
        try cancellation.check()
        for replica in unappliedPeerReplicas {
            try cancellation.check()
            let filteredRecords = replica.clipboard.records.filter {
                    $0.isFavorite && !tombstonedRecordNames.contains($0.recordName)
                        && removalsByContentID[$0.contentID]?.excludes($0) != true
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

        // 发布必须描述合并后的本地状态；收到远端记录本身不会产生本地 outbox。
        draft = try localRepository.exportDraft(
            deviceID: deviceID, generation: generation, revision: nextRevision,
            scope: .favoritesOnly
        )
        unavailableLocalRecordNames.formUnion(draft.unavailableClipboardRecordNames)
        let publishableDraft = draft
        let ownReplica = replicas.first { $0.manifest.deviceID == deviceID }
        let snapshotChanged = try ownReplica.map {
            try SyncSnapshotCodec.encode($0.clipboard.records) != SyncSnapshotCodec.encode(publishableDraft.clipboard.records)
                || SyncSnapshotCodec.encode($0.clipboard.favoriteRemovals) != SyncSnapshotCodec.encode(publishableDraft.clipboard.favoriteRemovals)
                || SyncSnapshotCodec.encode($0.preferences.domains) != SyncSnapshotCodec.encode(publishableDraft.preferences.domains)
                || SyncSnapshotCodec.encode($0.tombstones.records) != SyncSnapshotCodec.encode(publishableDraft.tombstones.records)
        } ?? true

        let hasMissingPublishedContent = publishableDraft.contentDescriptors.contains {
            !storedContentIDs.contains($0.contentID)
        }
        // 恢复本机较新云端副本时，任一对象缺失都必须保留其唯一发布点，直到全部导入。
        let needsWrite = !incompleteDeviceIDs.contains(deviceID) && (resetReplicaState
            || currentRevision == 0
            || ownReplicaUnverifiable
            || forceWrite
            || hasMissingPublishedContent
            || snapshotChanged)

        var writtenBundle: SyncExportBundle?
        var writtenManifestDigest: String?
        var writtenReplica: DriveSyncReplica?
        if needsWrite {
            // 完整校验过的本机旧发布点补入台账，成功发布新收藏快照后可安全回收旧正文快照。
            if let ownReplica, let directory = ownReplica.manifest.snapshotDirectory {
                let identity = SyncSnapshotPublicationIdentity(
                    storeID: descriptor.storeID, deviceID: deviceID, generation: generation,
                    revision: ownReplica.manifest.revision, snapshotDirectory: directory
                )
                if try localRepository.snapshotPublicationLedger.record(for: identity) == nil {
                    try localRepository.snapshotPublicationLedger.recordPrepared(.init(
                        storeID: descriptor.storeID, deviceID: deviceID, generation: generation,
                        revision: ownReplica.manifest.revision, snapshotDirectory: directory,
                        snapshotDigests: ownReplica.manifest.snapshotDigests,
                        manifestDigest: ownReplica.manifestDigest, state: .prepared,
                        supersededByRevision: nil, updatedAt: now
                    ))
                    try localRepository.snapshotPublicationLedger.markPublished(
                        identity, manifestDigest: ownReplica.manifestDigest, at: now
                    )
                }
            }
            // 从这里开始会改变目录；任一步失败都让下轮回退为完整 inventory 审计。
            invalidateObservationCache()
            try cancellation.check()
            seenRevisions[deviceID] = nextRevision
            let preparedDraft = draft
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
                // 不提前确认进度；下一轮必须把较新本机快照导入后才能确认或发布。
                invalidateObservationCache()
                throw DriveSyncCycleRetryError.newerRemoteReplica
            }
            storageInventory = storageInventory.adjustingMetadataBytes(
                by: writeResult.metadataByteDelta
            )
            try cancellation.check()
            let excludedRecordNames = unavailableLocalRecordNames
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
        } else if ownReplica != nil, !ownReplicaUnverifiable, !incompleteDeviceIDs.contains(deviceID),
                  try localRepository.hasPendingChanges(
                    excludingClipboardRecordNames: unavailableLocalRecordNames
                  ) {
            // 当前发布已准确表示草稿，无需为范围外复制或重复 outbox 再写相同快照。
            // 截止时间后的并发变化与不可用载荷仍保留，不把未上传对象标成已上传。
            try cancellation.check()
            try localRepository.acknowledgeSnapshot(
                upTo: draft.outboxCutoff,
                excludingClipboardRecordNames: unavailableLocalRecordNames
            )
        }

        var legacyCleanupProgress = cachedObservation?.legacyCleanupProgress
        // 回收是独立维护任务；稳定周期也分批推进，不能依赖再次复制才清理积压。
        if let currentReplica = writtenReplica ?? ownReplica, !ownReplicaUnverifiable {
            do {
                let reclaimedBytes = try store.cleanupSnapshotPublications(
                    storeID: descriptor.storeID, deviceID: deviceID, generation: generation,
                    protectedDirectories: Set([currentReplica.manifest.snapshotDirectory].compactMap { $0 }),
                    cancellation: cancellation
                )
                if legacyCleanupProgress?.revision != currentReplica.manifest.revision
                    || legacyCleanupProgress?.manifestDigest != currentReplica.manifestDigest {
                    legacyCleanupProgress = LegacyCleanupProgress(
                        revision: currentReplica.manifest.revision,
                        manifestDigest: currentReplica.manifestDigest,
                        lastScannedDirectory: nil, nextAuditAt: nil
                    )
                }
                var reclaimedLegacyBytes: Int64 = 0
                if legacyCleanupProgress?.nextAuditAt.map({ now >= $0 }) ?? true {
                    let batch = try store.cleanupLegacySnapshotBatch(
                        supersededBy: currentReplica,
                        afterDirectory: legacyCleanupProgress?.lastScannedDirectory,
                        cancellation: cancellation
                    )
                    reclaimedLegacyBytes = batch.reclaimedBytes
                    legacyCleanupProgress?.lastScannedDirectory = batch.didComplete ? nil : batch.lastScannedDirectory
                    legacyCleanupProgress?.nextAuditAt = batch.didComplete
                        ? now.addingTimeInterval(max(1, inventoryAuditInterval)) : nil
                }
                storageInventory = storageInventory.adjustingMetadataBytes(by: -reclaimedBytes - reclaimedLegacyBytes)
            } catch is SyncCycleCancellationError {
                invalidateObservationCache()
                throw SyncCycleCancellationError.cancelled
            } catch {
                invalidateObservationCache()
                storageInventory = try store.storageInventory(
                    revisionCache: revisionInventoryCache, cancellation: cancellation
                )
            }
        }

        var referencedContentIDs: Set<String> = []
        for replica in replicas where writtenBundle == nil || replica.manifest.deviceID != deviceID {
            // 离线旧设备仍引用的对象保留，直到设备升级重发收藏快照或被用户移除。
            referencedContentIDs.formUnion(replica.clipboard.records.map(\.contentID))
        }
        if let writtenBundle {
            referencedContentIDs.formUnion(writtenBundle.clipboard.records.map(\.contentID))
        }
        let storedObjects = storageInventory.objects
        var removedGarbageIDs: Set<String> = []
        if replicaFailures.isEmpty {
            var garbageIDs = try localRepository.garbageCollectionCandidates(
                allContentIDs: Set(storedObjects.map(\.contentID)),
                referencedContentIDs: referencedContentIDs,
                now: now
            )
            if !garbageIDs.isEmpty {
                do {
                    let retainedReferences = try store.retainedSnapshotContentIDs(cancellation: cancellation)
                    garbageIDs = try localRepository.garbageCollectionCandidates(
                        allContentIDs: Set(storedObjects.map(\.contentID)),
                        referencedContentIDs: referencedContentIDs.union(retainedReferences), now: now
                    )
                } catch is SyncCycleCancellationError {
                    throw SyncCycleCancellationError.cancelled
                } catch {
                    garbageIDs = []
                }
            }
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
        // 只复用已成功校验的副本；坏设备不清空健康设备及历史容量的观察。
        // 迟到或损坏内容单独刷新对象目录，下一周期仍能恢复，不重扫全部 revision。
        storeObservation(
            ObservationCache(
                rootURL: rootURL.standardizedFileURL,
                storeID: descriptor.storeID,
                generation: generation,
                replicasByDeviceID: reusableReplicasByDeviceID,
                replicaDigests: resultingReplicaDigests,
                removedDeviceIDs: removedDeviceIDs,
                inventory: finalStorageInventory,
                lastFullInventoryAuditAt: lastFullInventoryAuditAt,
                needsContentRefresh: missingRemoteContent || hasInvalidRemoteContent,
                legacyCleanupProgress: legacyCleanupProgress
            )
        )
        let usage = finalStorageInventory.usage(
            capacityBytes: configuration.storageLimit.byteLimit,
            ordinaryHistoryCount: 0
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
            remoteSettings: try remoteSettings ?? (peerReplicas.isEmpty ? nil : localRepository.currentSettings()),
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
