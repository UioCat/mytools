// `DriveSyncStore` 的同步核心领域实现。
// 负责协议模型、合并、对象存储和凭据对账，不管理 AppKit 生命周期。

import Foundation

/// 描述 `DriveSyncStoreError` 在同步核心领域中可取的状态、选项或错误。
public enum DriveSyncStoreError: Error, Equatable, Sendable {
    case missingProtocol
    case incompatibleProtocol(found: Int)
    case incompatibleSchema(fileName: String, found: Int)
    case itemNotDownloaded(URL)
    case invalidContentID(String)
    case snapshotDigestMismatch(deviceID: String, fileName: String)
    case inconsistentReplica(deviceID: String)
    case unreadableReplica(deviceID: String)
    case unreadableContent(String)
    case fileConflict(URL)
    case contentHashMismatch(String)
}

/// 封装 `DriveSyncReplica` 在同步核心领域中的值语义和相关操作。
public struct DriveSyncReplica: Equatable, Sendable {
    public var manifest: SyncReplicaManifest
    public var clipboard: SyncClipboardSnapshot
    public var preferences: SyncPreferencesSnapshot
    public var tombstones: SyncTombstoneSnapshot
    public var manifestDigest: String

    /// 创建 `DriveSyncReplica`，保存传入依赖并建立初始状态。
    public init(
        manifest: SyncReplicaManifest,
        clipboard: SyncClipboardSnapshot,
        preferences: SyncPreferencesSnapshot,
        tombstones: SyncTombstoneSnapshot,
        manifestDigest: String
    ) {
        self.manifest = manifest
        self.clipboard = clipboard
        self.preferences = preferences
        self.tombstones = tombstones
        self.manifestDigest = manifestDigest
    }
}

/// 封装 `SyncStoredObject` 在同步核心领域中的值语义和相关操作。
public struct SyncStoredObject: Equatable, Sendable {
    public var contentID: String
    public var kind: ClipboardContentKind
    public var byteCount: Int64

    /// 创建 `SyncStoredObject`，保存传入依赖并建立初始状态。
    public init(contentID: String, kind: ClipboardContentKind, byteCount: Int64) {
        self.contentID = contentID
        self.kind = kind
        self.byteCount = byteCount
    }
}

/// 封装 `SyncStorageInventory` 在同步核心领域中的值语义和相关操作。
public struct SyncStorageInventory: Equatable, Sendable {
    public var objects: [SyncStoredObject]
    public var imageBytes: Int64
    public var textBytes: Int64
    public var metadataBytes: Int64

    /// 创建 `SyncStorageInventory`，保存传入依赖并建立初始状态。
    public init(
        objects: [SyncStoredObject],
        imageBytes: Int64,
        textBytes: Int64,
        metadataBytes: Int64
    ) {
        self.objects = objects
        self.imageBytes = imageBytes
        self.textBytes = textBytes
        self.metadataBytes = metadataBytes
    }

    /// 使用已缓存清单和外部普通历史数量构造容量快照，避免重新扫描目录。
    public func usage(
        capacityBytes: Int64,
        ordinaryHistoryCount: Int
    ) -> SyncStorageUsage {
        SyncStorageUsage(
            usedBytes: imageBytes + textBytes + metadataBytes,
            capacityBytes: capacityBytes,
            ordinaryHistoryCount: ordinaryHistoryCount,
            imageBytes: imageBytes,
            textBytes: textBytes,
            metadataBytes: metadataBytes
        )
    }

    /// 从不可变清单移除指定内容对象并同步扣减分类字节数。
    public func removingObjects(withContentIDs contentIDs: Set<String>) -> Self {
        guard !contentIDs.isEmpty else { return self }
        var updated = self
        for object in objects where contentIDs.contains(object.contentID) {
            switch object.kind {
            case .imageData:
                updated.imageBytes = max(0, updated.imageBytes - object.byteCount)
            case .text, .url:
                updated.textBytes = max(0, updated.textBytes - object.byteCount)
            default:
                break
            }
        }
        updated.objects.removeAll { contentIDs.contains($0.contentID) }
        return updated
    }

    /// 使用本轮实际写入或修复的对象更新 inventory，不重新遍历同步根目录。
    public func applyingPreparedContents(
        _ descriptors: [SyncContentDescriptor],
        uploadedContentIDs: Set<String>
    ) -> Self {
        guard !uploadedContentIDs.isEmpty else { return self }
        var updated = self
        let descriptorsByID = Dictionary(
            uniqueKeysWithValues: descriptors.map { ($0.contentID, $0) }
        )
        for contentID in uploadedContentIDs {
            guard let descriptor = descriptorsByID[contentID] else { continue }
            if let existing = updated.objects.first(where: { $0.contentID == contentID }) {
                updated.subtractBytes(existing.byteCount, kind: existing.kind)
            }
            updated.objects.removeAll { $0.contentID == contentID }
            updated.objects.append(
                SyncStoredObject(
                    contentID: contentID,
                    kind: descriptor.kind,
                    byteCount: descriptor.storedByteCount
                )
            )
            updated.addBytes(descriptor.storedByteCount, kind: descriptor.kind)
        }
        updated.objects.sort { $0.contentID < $1.contentID }
        return updated
    }

    /// 应用已知元数据文件字节差，保持计数非负。
    public func adjustingMetadataBytes(by delta: Int64) -> Self {
        var updated = self
        updated.metadataBytes = max(0, updated.metadataBytes + delta)
        return updated
    }

    /// 按内容类型增加缓存统计；不计入当前同步协议不支持的载荷类型。
    private mutating func addBytes(_ bytes: Int64, kind: ClipboardContentKind) {
        switch kind {
        case .imageData:
            imageBytes += bytes
        case .text, .url:
            textBytes += bytes
        default:
            break
        }
    }

    /// 按内容类型扣减缓存统计，并将异常负数钳制为零。
    private mutating func subtractBytes(_ bytes: Int64, kind: ClipboardContentKind) {
        switch kind {
        case .imageData:
            imageBytes = max(0, imageBytes - bytes)
        case .text, .url:
            textBytes = max(0, textBytes - bytes)
        default:
            break
        }
    }
}

/// 封装 `DriveSyncReplicaFailure` 在同步核心领域中的值语义和相关操作。
public struct DriveSyncReplicaFailure: Equatable, Sendable {
    public var deviceID: String
    public var error: DriveSyncStoreError

    /// 创建 `DriveSyncReplicaFailure`，保存传入依赖并建立初始状态。
    public init(deviceID: String, error: DriveSyncStoreError) {
        self.deviceID = deviceID
        self.error = error
    }
}

/// 封装 `DriveSyncReplicaScan` 在同步核心领域中的值语义和相关操作。
public struct DriveSyncReplicaScan: Equatable, Sendable {
    public var replicas: [DriveSyncReplica]
    public var failures: [DriveSyncReplicaFailure]

    /// 创建 `DriveSyncReplicaScan`，保存传入依赖并建立初始状态。
    public init(replicas: [DriveSyncReplica], failures: [DriveSyncReplicaFailure]) {
        self.replicas = replicas
        self.failures = failures
    }
}

/// 按需准备共享内容对象后的可用、上传和不可用集合。
public struct SyncContentPreparationResult: Equatable, Sendable {
    public var availableContentIDs: Set<String>
    public var uploadedContentIDs: Set<String>
    public var unavailableContentIDs: Set<String>

    /// 汇总共享内容准备阶段的已有、刚上传和不可用对象集合。
    public init(
        availableContentIDs: Set<String> = [],
        uploadedContentIDs: Set<String> = [],
        unavailableContentIDs: Set<String> = []
    ) {
        self.availableContentIDs = availableContentIDs
        self.uploadedContentIDs = uploadedContentIDs
        self.unavailableContentIDs = unavailableContentIDs
    }
}

/// 发布设备 revision 后返回的 manifest 与可用于更新缓存的元数据字节差。
public struct DriveSyncWriteResult: Equatable, Sendable {
    public var manifest: SyncReplicaManifest
    public var manifestDigest: String
    public var metadataByteDelta: Int64

    /// 返回写入后的 manifest、摘要及元数据容量变化，供周期缓存原位更新。
    public init(
        manifest: SyncReplicaManifest,
        manifestDigest: String,
        metadataByteDelta: Int64
    ) {
        self.manifest = manifest
        self.manifestDigest = manifestDigest
        self.metadataByteDelta = metadataByteDelta
    }
}

/// 管理同步目录的协议、设备快照、内容对象和生命周期标记。
public final class DriveSyncStore: @unchecked Sendable {
    public static let rootDirectoryName = "MacTools Sync"

    public let rootURL: URL
    private let fileManager: FileManager

    /// 创建 `DriveSyncStore`，保存传入依赖并建立初始状态。
    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    /// 创建或校验同步目录协议结构，并在首次初始化时写入容量配置。
    @discardableResult
    public func prepare(
        initialCapacity: SyncStorageLimit = .default,
        now: Date = Date()
    ) throws -> SyncProtocolDescriptor {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for directory in [objectsTextURL, objectsImagesURL, replicasURL, evictionsURL, resetsURL, removedDevicesURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: keepURL.path) {
            try Data().write(to: keepURL, options: [.atomic])
        }
        if fileManager.fileExists(atPath: protocolURL.path) {
            return try readProtocol()
        }
        let descriptor = SyncProtocolDescriptor(
            storeID: UUID(),
            createdAt: now,
            capacityLimit: initialCapacity
        )
        try verifiedWrite(SyncSnapshotCodec.encode(descriptor), to: protocolURL)
        return descriptor
    }

    /// 读取并校验同步根目录协议描述；版本或结构不兼容时抛错。
    public func readProtocol() throws -> SyncProtocolDescriptor {
        guard fileManager.fileExists(atPath: protocolURL.path) else {
            throw DriveSyncStoreError.missingProtocol
        }
        let descriptor = try SyncSnapshotCodec.decode(
            SyncProtocolDescriptor.self,
            from: readData(at: protocolURL)
        )
        guard descriptor.protocolVersion == SyncProtocolDescriptor.currentVersion else {
            throw DriveSyncStoreError.incompatibleProtocol(found: descriptor.protocolVersion)
        }
        return descriptor
    }

    /// 读取指定 generation 下所有完整设备副本，跳过未下载或损坏目录。
    public func replicas(generation: Int) throws -> [DriveSyncReplica] {
        try scanReplicas(generation: generation).replicas
    }

    /// 每轮读取 manifest；摘要未变化时复用已校验 snapshot，变化时才读取 revision 内容。
    public func scanReplicas(
        generation: Int,
        cachedReplicasByDeviceID: [String: DriveSyncReplica] = [:]
    ) throws -> DriveSyncReplicaScan {
        guard fileManager.fileExists(atPath: replicasURL.path) else {
            return DriveSyncReplicaScan(replicas: [], failures: [])
        }
        let directories = try fileManager.contentsOfDirectory(
            at: replicasURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var replicas: [DriveSyncReplica] = []
        var failures: [DriveSyncReplicaFailure] = []
        for directory in directories {
            let deviceID = directory.lastPathComponent
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }
                if let replica = try readReplica(
                    at: directory,
                    generation: generation,
                    cachedReplica: cachedReplicasByDeviceID[deviceID]
                ) {
                    replicas.append(replica)
                }
            } catch let error as DriveSyncStoreError {
                failures.append(DriveSyncReplicaFailure(deviceID: deviceID, error: error))
            } catch {
                failures.append(
                    DriveSyncReplicaFailure(
                        deviceID: deviceID,
                        error: .unreadableReplica(deviceID: deviceID)
                    )
                )
            }
        }
        return DriveSyncReplicaScan(
            replicas: replicas.sorted { $0.manifest.deviceID < $1.manifest.deviceID },
            failures: failures.sorted { $0.deviceID < $1.deviceID }
        )
    }

    /// 先写内容对象和不可变 revision 目录，最后原子更新 manifest 作为发布点。
    public func write(
        _ bundle: SyncExportBundle,
        seenRevisions: [String: Int64],
        deviceName: String? = nil,
        updatedAt: Date,
        cancellation: SyncCycleCancellation = SyncCycleCancellation()
    ) throws -> SyncReplicaManifest {
        try writeWithMetadataDelta(
            bundle,
            seenRevisions: seenRevisions,
            deviceName: deviceName,
            updatedAt: updatedAt,
            cancellation: cancellation
        ).manifest
    }

    /// 写入设备 revision，并返回可直接合并进 inventory 缓存的元数据字节差。
    public func writeWithMetadataDelta(
        _ bundle: SyncExportBundle,
        seenRevisions: [String: Int64],
        deviceName: String? = nil,
        updatedAt: Date,
        cancellation: SyncCycleCancellation = SyncCycleCancellation()
    ) throws -> DriveSyncWriteResult {
        try cancellation.check()
        for content in bundle.contents {
            try cancellation.check()
            try writeContentIfNeeded(content)
        }

        try cancellation.check()
        let deviceDirectory = replicasURL.appendingPathComponent(
            bundle.clipboard.deviceID,
            isDirectory: true
        )
        let metadataBytesBeforeWrite = try regularFileBytes(in: deviceDirectory)
        try fileManager.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)

        let clipboardData = try SyncSnapshotCodec.encode(bundle.clipboard)
        let preferencesData = try SyncSnapshotCodec.encode(bundle.preferences)
        let tombstonesData = try SyncSnapshotCodec.encode(bundle.tombstones)
        // 摘要用于读取时发现损坏，不提供设备身份或写入者认证。
        let snapshotDigests = SyncSnapshotDigests(
            clipboard: SyncSnapshotCodec.digest(clipboardData),
            preferences: SyncSnapshotCodec.digest(preferencesData),
            tombstones: SyncSnapshotCodec.digest(tombstonesData)
        )
        let snapshotDirectoryName = Self.snapshotDirectoryName(
            generation: bundle.clipboard.generation,
            revision: bundle.clipboard.revision
        )
        let revisionsDirectory = deviceDirectory.appendingPathComponent("revisions", isDirectory: true)
        let snapshotDirectory = revisionsDirectory.appendingPathComponent(
            snapshotDirectoryName,
            isDirectory: true
        )
        try writeSnapshotRevision(
            clipboardData: clipboardData,
            preferencesData: preferencesData,
            tombstonesData: tombstonesData,
            to: snapshotDirectory,
            revisionsDirectory: revisionsDirectory
        )

        let manifest = SyncReplicaManifest(
            deviceID: bundle.clipboard.deviceID,
            deviceName: deviceName,
            generation: bundle.clipboard.generation,
            revision: bundle.clipboard.revision,
            seenRevisions: seenRevisions,
            snapshotDigests: snapshotDigests,
            snapshotDirectory: snapshotDirectoryName,
            updatedAt: updatedAt
        )
        let previousManifest = currentManifest(at: deviceDirectory)
        let manifestData = try SyncSnapshotCodec.encode(manifest)
        // manifest 是 revision 的唯一发布点，发布前必须重新确认周期仍有效。
        try cancellation.check()
        try verifiedWrite(
            manifestData,
            to: deviceDirectory.appendingPathComponent("manifest.json")
        )
        try removeObsoleteSnapshotRevisions(
            in: revisionsDirectory,
            keeping: Set([snapshotDirectoryName, previousManifest?.snapshotDirectory].compactMap { $0 })
        )
        let publishedManifest = try SyncSnapshotCodec.decode(
            SyncReplicaManifest.self,
            from: manifestData
        )
        let metadataBytesAfterWrite = try regularFileBytes(in: deviceDirectory)
        return DriveSyncWriteResult(
            manifest: publishedManifest,
            manifestDigest: SyncSnapshotCodec.digest(manifestData),
            metadataByteDelta: metadataBytesAfterWrite - metadataBytesBeforeWrite
        )
    }

    /// 只在共享对象缺失或损坏时调用 provider，并把单内容不可用隔离到结果中。
    public func prepareContents(
        _ descriptors: [SyncContentDescriptor],
        cancellation: SyncCycleCancellation = SyncCycleCancellation(),
        provider: (SyncContentDescriptor) throws -> SyncExportContent?
    ) throws -> SyncContentPreparationResult {
        var result = SyncContentPreparationResult()
        for descriptor in descriptors {
            try cancellation.check()
            let url = try contentURL(
                contentID: descriptor.contentID,
                kind: descriptor.kind
            )
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try validateContent(
                        readData(at: url, options: [.mappedIfSafe]),
                        contentID: descriptor.contentID,
                        kind: descriptor.kind
                    )
                    result.availableContentIDs.insert(descriptor.contentID)
                    continue
                } catch let error as DriveSyncStoreError {
                    switch error {
                    case .itemNotDownloaded, .fileConflict:
                        throw error
                    default:
                        break
                    }
                } catch {
                    // 损坏的共享对象可以由完整本地内容修复。
                }
            }

            guard let content = try provider(descriptor) else {
                result.unavailableContentIDs.insert(descriptor.contentID)
                continue
            }
            guard content.contentID == descriptor.contentID,
                  content.kind == descriptor.kind else {
                result.unavailableContentIDs.insert(descriptor.contentID)
                continue
            }
            do {
                try validateContent(
                    content.data,
                    contentID: descriptor.contentID,
                    kind: descriptor.kind
                )
            } catch {
                result.unavailableContentIDs.insert(descriptor.contentID)
                continue
            }
            try cancellation.check()
            try verifiedWrite(content.data, to: url)
            result.availableContentIDs.insert(descriptor.contentID)
            result.uploadedContentIDs.insert(descriptor.contentID)
        }
        return result
    }

    /// 读取并校验共享内容对象；文件尚未下载时返回 nil 供下轮重试。
    public func contentData(contentID: String, kind: ClipboardContentKind) throws -> Data? {
        let url = try contentURL(contentID: contentID, kind: kind)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try readData(at: url, options: [.mappedIfSafe])
        } catch let error as DriveSyncStoreError {
            throw error
        } catch {
            throw DriveSyncStoreError.unreadableContent(contentID)
        }
        try validateContent(data, contentID: contentID, kind: kind)
        return data
    }

    /// 校验内容摘要与类型后返回共享对象的规范文件 URL。
    public func contentFileURL(contentID: String, kind: ClipboardContentKind) throws -> URL {
        try contentURL(contentID: contentID, kind: kind)
    }

    /// 原子写入容量淘汰快照，并返回元数据字节变化。
    @discardableResult
    public func writeEvictions(_ snapshot: SyncEvictionSnapshot) throws -> Int64 {
        let url = evictionsURL.appendingPathComponent("\(snapshot.deviceID).json")
        let bytesBeforeWrite = try regularFileBytes(at: url)
        let data = try SyncSnapshotCodec.encode(snapshot)
        try verifiedWrite(data, to: url)
        return Int64(data.count) - bytesBeforeWrite
    }

    /// 移除 `evictions` 指定的同步核心领域数据，并维护关联状态。
    public func evictions(generation: Int) throws -> [SyncEvictionRecord] {
        try jsonFiles(in: evictionsURL).flatMap { url -> [SyncEvictionRecord] in
            let snapshot = try SyncSnapshotCodec.decode(
                SyncEvictionSnapshot.self,
                from: readData(at: url)
            )
            try validateSchema(
                snapshot.schemaVersion,
                expected: SyncEvictionSnapshot.currentSchemaVersion,
                fileName: url.lastPathComponent
            )
            guard snapshot.generation == generation else { return [] }
            return snapshot.records
        }
    }

    /// 移除 `evictionSnapshot` 指定的同步核心领域数据，并维护关联状态。
    public func evictionSnapshot(deviceID: String) throws -> SyncEvictionSnapshot? {
        let url = evictionsURL.appendingPathComponent("\(deviceID).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let snapshot = try SyncSnapshotCodec.decode(
            SyncEvictionSnapshot.self,
            from: readData(at: url)
        )
        try validateSchema(
            snapshot.schemaVersion,
            expected: SyncEvictionSnapshot.currentSchemaVersion,
            fileName: url.lastPathComponent
        )
        return snapshot
    }

    /// 写入 generation 重置标记，使所有设备在下一周期采用新代际。
    public func writeReset(_ marker: SyncResetMarker) throws {
        try verifiedWrite(
            SyncSnapshotCodec.encode(marker),
            to: resetsURL.appendingPathComponent("\(marker.deviceID).json")
        )
    }

    /// 扫描有效重置标记并返回最高 generation，缺失时返回协议初始值。
    public func highestResetGeneration() throws -> Int {
        try jsonFiles(in: resetsURL).reduce(1) { value, url in
            let marker = try SyncSnapshotCodec.decode(
                SyncResetMarker.self,
                from: readData(at: url)
            )
            try validateSchema(
                marker.schemaVersion,
                expected: SyncResetMarker.currentSchemaVersion,
                fileName: url.lastPathComponent
            )
            return max(value, marker.generation)
        }
    }

    /// 原子写入设备移除标记，阻止已移除副本继续参与合并和垃圾回收确认。
    public func writeRemovedDevice(_ marker: SyncRemovedDeviceMarker) throws {
        let directory = removedDevicesURL.appendingPathComponent(
            marker.removedDeviceID,
            isDirectory: true
        )
        try verifiedWrite(
            SyncSnapshotCodec.encode(marker),
            to: directory.appendingPathComponent("\(marker.removerDeviceID).json")
        )
    }

    /// 移除 `removedDeviceIDs` 指定的同步核心领域数据，并维护关联状态。
    public func removedDeviceIDs(generation: Int) throws -> Set<String> {
        guard fileManager.fileExists(atPath: removedDevicesURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: removedDevicesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var removed: Set<String> = []
        for directory in directories {
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            for url in try jsonFiles(in: directory) {
                let marker = try SyncSnapshotCodec.decode(
                    SyncRemovedDeviceMarker.self,
                    from: readData(at: url)
                )
                try validateSchema(
                    marker.schemaVersion,
                    expected: SyncRemovedDeviceMarker.currentSchemaVersion,
                    fileName: url.lastPathComponent
                )
                guard marker.generation <= generation,
                      marker.removedDeviceID == directory.lastPathComponent else {
                    continue
                }
                removed.insert(marker.removedDeviceID)
            }
        }
        return removed
    }

    /// 通过一次目录盘点计算当前容量使用和普通历史数量。
    public func usage(capacityBytes: Int64, ordinaryHistoryCount: Int) throws -> SyncStorageUsage {
        try storageInventory().usage(
            capacityBytes: capacityBytes,
            ordinaryHistoryCount: ordinaryHistoryCount
        )
    }

    /// 递归盘点共享内容、设备快照和协议元数据，形成可缓存清单。
    public func storageInventory() throws -> SyncStorageInventory {
        var objects: [SyncStoredObject] = []
        var imageBytes: Int64 = 0
        var textBytes: Int64 = 0
        var metadataBytes: Int64 = 0
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return SyncStorageInventory(
                objects: [],
                imageBytes: 0,
                textBytes: 0,
                metadataBytes: 0
            )
        }
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let bytes = Int64(values.fileSize ?? 0)
            let directoryKind = storedObjectDirectoryKind(for: url)
            if directoryKind == .imageData {
                imageBytes += bytes
            } else if directoryKind == .text {
                textBytes += bytes
            } else {
                metadataBytes += bytes
            }
            guard let directoryKind else { continue }
            let expectedExtension = directoryKind == .imageData ? "png" : "json"
            guard url.pathExtension == expectedExtension else { continue }
            let contentID = url.deletingPathExtension().lastPathComponent
            guard Self.isValidContentID(contentID) else { continue }
            objects.append(
                SyncStoredObject(
                    contentID: contentID,
                    kind: directoryKind,
                    byteCount: bytes
                )
            )
        }
        return SyncStorageInventory(
            objects: objects.sorted { $0.contentID < $1.contentID },
            imageBytes: imageBytes,
            textBytes: textBytes,
            metadataBytes: metadataBytes
        )
    }

    /// 将共享对象一级目录映射为协议支持的内容类型。
    private func storedObjectDirectoryKind(for url: URL) -> ClipboardContentKind? {
        let components = url.pathComponents
        guard let objectsIndex = components.lastIndex(of: "objects"),
              components.indices.contains(objectsIndex + 2),
              components[objectsIndex + 2] == "sha256" else {
            return nil
        }
        switch components[objectsIndex + 1] {
        case "text": return .text
        case "images": return .imageData
        default: return nil
        }
    }

    /// 移除 `removeReplicaData` 指定的同步核心领域数据，并维护关联状态。
    public func removeReplicaData() throws {
        for url in [replicasURL, evictionsURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// removal marker 生效且接管 revision 发布后，物理清理指定设备的副本与 eviction。
    public func removeDeviceData(
        deviceID: String,
        cancellation: SyncCycleCancellation = SyncCycleCancellation()
    ) throws {
        guard Self.isValidPathComponent(deviceID) else {
            throw DriveSyncStoreError.inconsistentReplica(deviceID: deviceID)
        }
        let targets = [
            replicasURL.appendingPathComponent(deviceID, isDirectory: true),
            evictionsURL.appendingPathComponent("\(deviceID).json")
        ]
        for target in targets {
            try cancellation.check()
            guard fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.removeItem(at: target)
        }
    }

    /// 枚举并校验所有共享内容对象的摘要、类型和字节数。
    public func storedObjects() throws -> [SyncStoredObject] {
        try storageInventory().objects
    }

    /// 移除 `removeObject` 指定的同步核心领域数据，并维护关联状态。
    public func removeObject(_ object: SyncStoredObject) throws {
        let url = try contentURL(contentID: object.contentID, kind: object.kind)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let data = try readData(at: url, options: [.mappedIfSafe])
        if object.kind == .text {
            let decoded = try SyncSnapshotCodec.decode(SyncTextContentObject.self, from: data)
            try validateContent(data, contentID: object.contentID, kind: decoded.kind)
        } else {
            try validateContent(data, contentID: object.contentID, kind: object.kind)
        }
        try fileManager.removeItem(at: url)
    }

    /// 读取 manifest 指向的 revision，并校验 generation、设备 ID 和所有快照摘要。
    private func readReplica(
        at directory: URL,
        generation: Int,
        cachedReplica: DriveSyncReplica?
    ) throws -> DriveSyncReplica? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let manifestData = try readData(at: manifestURL)
        let manifest = try SyncSnapshotCodec.decode(SyncReplicaManifest.self, from: manifestData)
        guard [1, SyncReplicaManifest.currentSchemaVersion].contains(manifest.schemaVersion) else {
            throw DriveSyncStoreError.incompatibleSchema(
                fileName: manifestURL.lastPathComponent,
                found: manifest.schemaVersion
            )
        }
        guard manifest.generation == generation else { return nil }
        guard manifest.deviceID == directory.lastPathComponent else {
            throw DriveSyncStoreError.inconsistentReplica(deviceID: directory.lastPathComponent)
        }
        let manifestDigest = SyncSnapshotCodec.digest(manifestData)
        if let cachedReplica,
           cachedReplica.manifestDigest == manifestDigest,
           cachedReplica.manifest == manifest {
            return cachedReplica
        }

        let snapshotDirectory: URL
        if let snapshotDirectoryName = manifest.snapshotDirectory {
            guard Self.isValidSnapshotDirectoryName(snapshotDirectoryName) else {
                throw DriveSyncStoreError.inconsistentReplica(deviceID: manifest.deviceID)
            }
            snapshotDirectory = directory
                .appendingPathComponent("revisions", isDirectory: true)
                .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
        } else {
            snapshotDirectory = directory
        }
        let clipboardData = try snapshotData(
            named: "clipboard.json",
            expectedDigest: manifest.snapshotDigests.clipboard,
            deviceID: manifest.deviceID,
            directory: snapshotDirectory
        )
        let preferencesData = try snapshotData(
            named: "preferences.json",
            expectedDigest: manifest.snapshotDigests.preferences,
            deviceID: manifest.deviceID,
            directory: snapshotDirectory
        )
        let tombstonesData = try snapshotData(
            named: "tombstones.json",
            expectedDigest: manifest.snapshotDigests.tombstones,
            deviceID: manifest.deviceID,
            directory: snapshotDirectory
        )
        let clipboard = try SyncSnapshotCodec.decode(SyncClipboardSnapshot.self, from: clipboardData)
        let preferences = try SyncSnapshotCodec.decode(SyncPreferencesSnapshot.self, from: preferencesData)
        let tombstones = try SyncSnapshotCodec.decode(SyncTombstoneSnapshot.self, from: tombstonesData)
        try validateSchema(
            clipboard.schemaVersion,
            expected: SyncClipboardSnapshot.currentSchemaVersion,
            fileName: "clipboard.json"
        )
        try validateSchema(
            preferences.schemaVersion,
            expected: SyncPreferencesSnapshot.currentSchemaVersion,
            fileName: "preferences.json"
        )
        try validateSchema(
            tombstones.schemaVersion,
            expected: SyncTombstoneSnapshot.currentSchemaVersion,
            fileName: "tombstones.json"
        )
        guard clipboard.deviceID == manifest.deviceID,
              preferences.deviceID == manifest.deviceID,
              tombstones.deviceID == manifest.deviceID,
              clipboard.revision == manifest.revision,
              preferences.revision == manifest.revision,
              tombstones.revision == manifest.revision,
              clipboard.generation == generation,
              preferences.generation == generation,
              tombstones.generation == generation else {
            throw DriveSyncStoreError.inconsistentReplica(deviceID: manifest.deviceID)
        }
        return DriveSyncReplica(
            manifest: manifest,
            clipboard: clipboard,
            preferences: preferences,
            tombstones: tombstones,
            manifestDigest: manifestDigest
        )
    }

    /// 从设备快照目录读取指定 JSON；未下载文件返回 nil，损坏内容抛错。
    private func snapshotData(
        named fileName: String,
        expectedDigest: String,
        deviceID: String,
        directory: URL
    ) throws -> Data {
        let data = try readData(at: directory.appendingPathComponent(fileName))
        guard SyncSnapshotCodec.digest(data) == expectedDigest else {
            throw DriveSyncStoreError.snapshotDigestMismatch(
                deviceID: deviceID,
                fileName: fileName
            )
        }
        return data
    }

    /// 原子写入单个 revision 快照并返回写入前后的元数据字节差。
    private func writeSnapshotRevision(
        clipboardData: Data,
        preferencesData: Data,
        tombstonesData: Data,
        to destination: URL,
        revisionsDirectory: URL
    ) throws {
        try fileManager.createDirectory(at: revisionsDirectory, withIntermediateDirectories: true)
        let staging = revisionsDirectory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try verifiedWrite(clipboardData, to: staging.appendingPathComponent("clipboard.json"))
            try verifiedWrite(preferencesData, to: staging.appendingPathComponent("preferences.json"))
            try verifiedWrite(tombstonesData, to: staging.appendingPathComponent("tombstones.json"))
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// 尝试读取设备当前 manifest；不存在、未下载或损坏时返回 nil 触发完整重写。
    private func currentManifest(at deviceDirectory: URL) -> SyncReplicaManifest? {
        let url = deviceDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? readData(at: url) else {
            return nil
        }
        return try? SyncSnapshotCodec.decode(SyncReplicaManifest.self, from: data)
    }

    /// 移除 `removeObsoleteSnapshotRevisions` 指定的同步核心领域数据，并维护关联状态。
    private func removeObsoleteSnapshotRevisions(
        in revisionsDirectory: URL,
        keeping names: Set<String>
    ) throws {
        guard fileManager.fileExists(atPath: revisionsDirectory.path) else { return }
        for url in try fileManager.contentsOfDirectory(
            at: revisionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) where !names.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
        }
    }

    /// 仅在共享对象不存在时写入内容，并通过摘要回读验证写入结果。
    private func writeContentIfNeeded(_ content: SyncExportContent) throws {
        let url = try contentURL(contentID: content.contentID, kind: content.kind)
        try validateContent(content.data, contentID: content.contentID, kind: content.kind)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try validateContent(
                    readData(at: url, options: [.mappedIfSafe]),
                    contentID: content.contentID,
                    kind: content.kind
                )
                return
            } catch let error as DriveSyncStoreError {
                switch error {
                case .itemNotDownloaded, .fileConflict:
                    throw error
                default:
                    break
                }
            } catch {
                // 本地对象已经通过完整性校验；没有 iCloud 冲突时，
                // 可以用它修复同一内容寻址路径上的损坏字节。
            }
            try verifiedWrite(content.data, to: url)
            return
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try verifiedWrite(content.data, to: url)
    }

    /// 校验 `validateContent` 接收的同步核心领域数据是否满足当前约束。
    private func validateContent(_ data: Data, contentID: String, kind: ClipboardContentKind) throws {
        let actualHash: String
        switch kind {
        case .text, .url:
            let object: SyncTextContentObject
            do {
                object = try SyncSnapshotCodec.decode(SyncTextContentObject.self, from: data)
            } catch {
                throw DriveSyncStoreError.contentHashMismatch(contentID)
            }
            try validateSchema(
                object.schemaVersion,
                expected: SyncTextContentObject.currentSchemaVersion,
                fileName: "\(contentID).json"
            )
            guard object.contentID == contentID, object.kind == kind else {
                throw DriveSyncStoreError.contentHashMismatch(contentID)
            }
            actualHash = ClipboardContentHasher.sha256String(
                for: Data("text:\(object.text)".utf8)
            )
        case .imageData:
            guard PayloadStore.isValidPNGData(data) else {
                throw DriveSyncStoreError.contentHashMismatch(contentID)
            }
            actualHash = ClipboardContentHasher.sha256String(for: data)
        default:
            throw DriveSyncStoreError.contentHashMismatch(contentID)
        }
        guard actualHash == contentID else {
            throw DriveSyncStoreError.contentHashMismatch(contentID)
        }
    }

    /// 校验摘要和类型后构造内容寻址对象路径，拒绝目录穿越输入。
    private func contentURL(contentID: String, kind: ClipboardContentKind) throws -> URL {
        guard Self.isValidContentID(contentID) else {
            throw DriveSyncStoreError.invalidContentID(contentID)
        }
        let prefix = String(contentID.prefix(2))
        switch kind {
        case .text, .url:
            return objectsTextURL
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(contentID)
                .appendingPathExtension("json")
        case .imageData:
            return objectsImagesURL
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(contentID)
                .appendingPathExtension("png")
        default:
            throw DriveSyncStoreError.invalidContentID(contentID)
        }
    }

    /// 使用 staging 文件、原子替换和写后回读保证元数据文件完整可见。
    private func verifiedWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: url.path) {
            try resolveIdenticalConflicts(at: url)
        }
        try data.write(to: url, options: [.atomic])
        guard try readData(at: url) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// 请求 iCloud 下载并读取文件；可选缺失文件返回 nil，必需文件缺失抛错。
    private func readData(
        at url: URL,
        options: Data.ReadingOptions = []
    ) throws -> Data {
        if fileManager.isUbiquitousItem(at: url) {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus != .current {
                throw DriveSyncStoreError.itemNotDownloaded(url)
            }
        }
        try resolveIdenticalConflicts(at: url)
        return try Data(contentsOf: url, options: options)
    }

    /// 解析并返回 `resolveIdenticalConflicts` 对应的同步核心领域结果。
    private func resolveIdenticalConflicts(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else {
            return
        }
        let currentData = try Data(contentsOf: url, options: [.mappedIfSafe])
        for conflict in conflicts {
            guard conflict.hasLocalContents,
                  (try? Data(contentsOf: conflict.url, options: [.mappedIfSafe])) == currentData else {
                throw DriveSyncStoreError.fileConflict(url)
            }
        }
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    /// 校验 `validateSchema` 接收的同步核心领域数据是否满足当前约束。
    private func validateSchema(_ found: Int, expected: Int, fileName: String) throws {
        guard found == expected else {
            throw DriveSyncStoreError.incompatibleSchema(fileName: fileName, found: found)
        }
    }

    /// 返回目录下按文件名排序的普通 JSON 文件，便于确定性合并。
    private func jsonFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 读取单文件大小；文件不存在时返回 0。
    private func regularFileBytes(at url: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    /// 统计一个局部目录下的普通文件大小，只用于实际写入周期的 delta。
    private func regularFileBytes(in directory: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var bytes: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        return bytes
    }

    /// 只接受 64 位小写十六进制 SHA-256 内容标识。
    private static func isValidContentID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    /// 校验设备 ID 可安全作为单个目录或文件名使用。
    private static func isValidPathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 255
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.hasPrefix(".")
    }

    /// 使用 generation 和 revision 生成不可变设备快照目录名。
    private static func snapshotDirectoryName(generation: Int, revision: Int64) -> String {
        "g\(generation)-r\(revision)-\(UUID().uuidString.lowercased())"
    }

    /// 校验快照目录名严格符合 generation-revision 协议格式。
    private static func isValidSnapshotDirectoryName(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 160
            && !value.hasPrefix(".")
            && !value.contains("/")
            && !value.contains("..")
    }

    private var protocolURL: URL { rootURL.appendingPathComponent("protocol.json") }
    private var keepURL: URL { rootURL.appendingPathComponent(".mactools-keep") }
    private var replicasURL: URL { rootURL.appendingPathComponent("replicas", isDirectory: true) }
    private var evictionsURL: URL { rootURL.appendingPathComponent("evictions", isDirectory: true) }
    private var resetsURL: URL { rootURL.appendingPathComponent("resets", isDirectory: true) }
    private var removedDevicesURL: URL { rootURL.appendingPathComponent("removed-devices", isDirectory: true) }
    private var objectsTextURL: URL {
        rootURL.appendingPathComponent("objects/text/sha256", isDirectory: true)
    }
    private var objectsImagesURL: URL {
        rootURL.appendingPathComponent("objects/images/sha256", isDirectory: true)
    }
}
