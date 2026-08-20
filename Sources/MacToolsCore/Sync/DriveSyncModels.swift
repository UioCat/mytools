// `DriveSyncModels` 的同步核心领域实现。
// 负责协议模型、合并、对象存储和凭据对账，不管理 AppKit 生命周期。

import Foundation

/// 描述 `SyncRecordType` 在同步核心领域中可取的状态、选项或错误。
public enum SyncRecordType: String, Codable, Equatable, Sendable {
    case clipboardContent
    case preferenceDomain
    case tombstone
    case deviceReplica
}

/// 描述 `SyncStorageLimit` 在同步核心领域中可取的状态、选项或错误。
public enum SyncStorageLimit: Int, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case megabytes256 = 256
    case megabytes512 = 512
    case gigabyte1 = 1_024
    case gigabytes2 = 2_048

    public static let `default` = SyncStorageLimit.megabytes512

    public var id: Int { rawValue }
    public var byteLimit: Int64 { Int64(rawValue) * 1_024 * 1_024 }

    public var displayName: String {
        switch self {
        case .megabytes256: return "256 MB"
        case .megabytes512: return "512 MB"
        case .gigabyte1: return "1 GB"
        case .gigabytes2: return "2 GB"
        }
    }
}

/// 封装 `SyncProtocolDescriptor` 在同步核心领域中的值语义和相关操作。
public struct SyncProtocolDescriptor: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var protocolVersion: Int
    public var storeID: UUID
    public var createdAt: Date
    public var capacityLimit: SyncStorageLimit

    /// 创建 `SyncProtocolDescriptor`，保存传入依赖并建立初始状态。
    public init(
        protocolVersion: Int = Self.currentVersion,
        storeID: UUID,
        createdAt: Date,
        capacityLimit: SyncStorageLimit = .default
    ) {
        self.protocolVersion = protocolVersion
        self.storeID = storeID
        self.createdAt = createdAt
        self.capacityLimit = capacityLimit
    }
}

/// 封装 `SyncSnapshotDigests` 在同步核心领域中的值语义和相关操作。
public struct SyncSnapshotDigests: Codable, Equatable, Sendable {
    public var clipboard: String
    public var preferences: String
    public var tombstones: String

    /// 创建 `SyncSnapshotDigests`，保存传入依赖并建立初始状态。
    public init(clipboard: String, preferences: String, tombstones: String) {
        self.clipboard = clipboard
        self.preferences = preferences
        self.tombstones = tombstones
    }
}

/// 封装 `SyncReplicaManifest` 在同步核心领域中的值语义和相关操作。
public struct SyncReplicaManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var deviceID: String
    public var deviceName: String?
    public var generation: Int
    public var revision: Int64
    public var seenRevisions: [String: Int64]
    public var snapshotDigests: SyncSnapshotDigests
    public var snapshotDirectory: String?
    public var updatedAt: Date

    /// 创建 `SyncReplicaManifest`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceID: String,
        deviceName: String? = nil,
        generation: Int,
        revision: Int64,
        seenRevisions: [String: Int64],
        snapshotDigests: SyncSnapshotDigests,
        snapshotDirectory: String? = nil,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.generation = generation
        self.revision = revision
        self.seenRevisions = seenRevisions
        self.snapshotDigests = snapshotDigests
        self.snapshotDirectory = snapshotDirectory
        self.updatedAt = updatedAt
    }
}

/// 封装 `SyncDeviceSummary` 在同步核心领域中的值语义和相关操作。
public struct SyncDeviceSummary: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isCurrentDevice: Bool
    public var lastUpdatedAt: Date?

    /// 创建 `SyncDeviceSummary`，保存传入依赖并建立初始状态。
    public init(
        id: String,
        name: String,
        isCurrentDevice: Bool,
        lastUpdatedAt: Date?
    ) {
        self.id = id
        self.name = name
        self.isCurrentDevice = isCurrentDevice
        self.lastUpdatedAt = lastUpdatedAt
    }
}

/// 封装 `SyncClipboardRecord` 在同步核心领域中的值语义和相关操作。
public struct SyncClipboardRecord: Codable, Equatable, Sendable {
    public var recordName: String
    public var contentID: String
    public var kind: ClipboardContentKind
    public var displayTitle: String
    public var searchableText: String
    public var sourceApp: String?
    public var createdAt: Date
    public var lastCapturedAt: Date
    public var lastUsedAt: Date?
    public var retentionAt: Date
    public var useCount: Int
    public var isPinned: Bool
    public var isFavorite: Bool
    public var tags: [String]
    public var favoriteClock: ClipboardFieldClock
    public var tagsClock: ClipboardFieldClock
    public var pinnedClock: ClipboardFieldClock

    /// 创建 `SyncClipboardRecord`，保存传入依赖并建立初始状态。
    public init(
        recordName: String,
        contentID: String,
        kind: ClipboardContentKind,
        displayTitle: String,
        searchableText: String,
        sourceApp: String?,
        createdAt: Date,
        lastCapturedAt: Date,
        lastUsedAt: Date?,
        retentionAt: Date,
        useCount: Int,
        isPinned: Bool,
        isFavorite: Bool,
        tags: [String] = [],
        favoriteClock: ClipboardFieldClock,
        tagsClock: ClipboardFieldClock = .zero,
        pinnedClock: ClipboardFieldClock
    ) {
        self.recordName = recordName
        self.contentID = contentID
        self.kind = kind
        self.displayTitle = displayTitle
        self.searchableText = searchableText
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.lastCapturedAt = lastCapturedAt
        self.lastUsedAt = lastUsedAt
        self.retentionAt = retentionAt
        self.useCount = useCount
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.tags = ClipboardTagPolicy.normalized(tags)
        self.favoriteClock = favoriteClock
        self.tagsClock = tagsClock
        self.pinnedClock = pinnedClock
    }

    private enum CodingKeys: String, CodingKey {
        case recordName
        case contentID
        case kind
        case displayTitle
        case searchableText
        case sourceApp
        case createdAt
        case lastCapturedAt
        case lastUsedAt
        case retentionAt
        case useCount
        case isPinned
        case isFavorite
        case tags
        case favoriteClock
        case tagsClock
        case pinnedClock
    }

    /// 解码同步记录；旧快照缺少标签字段时使用空集合和零时钟。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recordName = try container.decode(String.self, forKey: .recordName)
        self.contentID = try container.decode(String.self, forKey: .contentID)
        self.kind = try container.decode(ClipboardContentKind.self, forKey: .kind)
        self.displayTitle = try container.decode(String.self, forKey: .displayTitle)
        self.searchableText = try container.decode(String.self, forKey: .searchableText)
        self.sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastCapturedAt = try container.decode(Date.self, forKey: .lastCapturedAt)
        self.lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        self.retentionAt = try container.decode(Date.self, forKey: .retentionAt)
        self.useCount = try container.decode(Int.self, forKey: .useCount)
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        self.tags = ClipboardTagPolicy.normalized(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
        self.favoriteClock = try container.decode(ClipboardFieldClock.self, forKey: .favoriteClock)
        self.tagsClock = try container.decodeIfPresent(
            ClipboardFieldClock.self,
            forKey: .tagsClock
        ) ?? .zero
        self.pinnedClock = try container.decode(ClipboardFieldClock.self, forKey: .pinnedClock)
    }
}

/// 封装 `SyncClipboardSnapshot` 在同步核心领域中的值语义和相关操作。
public struct SyncClipboardSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var records: [SyncClipboardRecord]

    /// 创建 `SyncClipboardSnapshot`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceID: String,
        generation: Int,
        revision: Int64,
        records: [SyncClipboardRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.generation = generation
        self.revision = revision
        self.records = records
    }
}

/// 封装 `SyncTextContentObject` 在同步核心领域中的值语义和相关操作。
public struct SyncTextContentObject: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var contentID: String
    public var kind: ClipboardContentKind
    public var text: String
    public var byteCount: Int64

    /// 创建 `SyncTextContentObject`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        contentID: String,
        kind: ClipboardContentKind,
        text: String,
        byteCount: Int64
    ) {
        self.schemaVersion = schemaVersion
        self.contentID = contentID
        self.kind = kind
        self.text = text
        self.byteCount = byteCount
    }
}

/// 封装 `SyncExportContent` 在同步核心领域中的值语义和相关操作。
public struct SyncExportContent: Equatable, Sendable {
    public var contentID: String
    public var kind: ClipboardContentKind
    public var data: Data

    /// 创建 `SyncExportContent`，保存传入依赖并建立初始状态。
    public init(contentID: String, kind: ClipboardContentKind, data: Data) {
        self.contentID = contentID
        self.kind = kind
        self.data = data
    }
}

/// 描述同步内容的本地来源；导出阶段不读取或持有实体 Data。
public enum SyncContentSource: Equatable, Sendable {
    case text(String)
    case payloadFile(URL)
}

/// 容量决策和按需物化使用的内容描述符，不参与远端协议编码。
public struct SyncContentDescriptor: Equatable, Sendable {
    public var contentID: String
    public var kind: ClipboardContentKind
    public var storedByteCount: Int64
    public var source: SyncContentSource

    /// 描述一个尚未物化的同步内容对象及其本地来源和容量占用。
    public init(
        contentID: String,
        kind: ClipboardContentKind,
        storedByteCount: Int64,
        source: SyncContentSource
    ) {
        self.contentID = contentID
        self.kind = kind
        self.storedByteCount = storedByteCount
        self.source = source
    }
}

/// 不含内容 Data 的本地同步草稿；两次导出和容量裁剪都使用该模型。
public struct SyncExportDraft: Equatable, Sendable {
    public var clipboard: SyncClipboardSnapshot
    public var preferences: SyncPreferencesSnapshot
    public var tombstones: SyncTombstoneSnapshot
    public var contentDescriptors: [SyncContentDescriptor]
    public var outboxCutoff: Date
    public var unavailableClipboardRecordNames: Set<String>

    /// 建立一次同步导出草稿；outbox 截止时间用于成功后确认本轮已发布变更。
    public init(
        clipboard: SyncClipboardSnapshot,
        preferences: SyncPreferencesSnapshot,
        tombstones: SyncTombstoneSnapshot,
        contentDescriptors: [SyncContentDescriptor],
        outboxCutoff: Date,
        unavailableClipboardRecordNames: Set<String> = []
    ) {
        self.clipboard = clipboard
        self.preferences = preferences
        self.tombstones = tombstones
        self.contentDescriptors = contentDescriptors
        self.outboxCutoff = outboxCutoff
        self.unavailableClipboardRecordNames = unavailableClipboardRecordNames
    }

    /// 同时移除被容量策略淘汰的内容描述符和引用记录，保持导出快照自洽。
    public func excludingContentIDs(_ excludedContentIDs: Set<String>) -> Self {
        guard !excludedContentIDs.isEmpty else { return self }
        var filtered = self
        filtered.clipboard.records.removeAll {
            excludedContentIDs.contains($0.contentID)
        }
        filtered.contentDescriptors.removeAll {
            excludedContentIDs.contains($0.contentID)
        }
        return filtered
    }

    /// 将草稿与已经按需物化的内容合并为可写入远端目录的导出包。
    public func bundle(contents: [SyncExportContent] = []) -> SyncExportBundle {
        SyncExportBundle(
            clipboard: clipboard,
            preferences: preferences,
            tombstones: tombstones,
            contents: contents,
            outboxCutoff: outboxCutoff,
            unavailableClipboardRecordNames: unavailableClipboardRecordNames
        )
    }
}

/// 封装 `SyncExportContentCache` 在同步核心领域中的值语义和相关操作。
public struct SyncExportContentCache: Sendable {
    /// 封装 `Key` 在同步核心领域中的值语义和相关操作。
    private struct Key: Hashable, Sendable {
        var kind: String
        var contentID: String
    }

    private var contentsByKey: [Key: SyncExportContent] = [:]
    public private(set) var materializedContentCount = 0

    /// 创建 `SyncExportContentCache`，保存传入依赖并建立初始状态。
    public init() {}

    /// 计算并返回 `content` 对应的同步核心领域数据或状态结果。
    func content(kind: ClipboardContentKind, contentID: String) -> SyncExportContent? {
        contentsByKey[Key(kind: kind.rawValue, contentID: contentID)]
    }

    /// 保存 `store` 接收的同步核心领域数据，并保持既有持久化约束。
    mutating func store(_ content: SyncExportContent) {
        let key = Key(kind: content.kind.rawValue, contentID: content.contentID)
        guard contentsByKey[key] == nil else { return }
        contentsByKey[key] = content
        materializedContentCount += 1
    }
}

/// 封装 `SyncExportBundle` 在同步核心领域中的值语义和相关操作。
public struct SyncExportBundle: Equatable, Sendable {
    public var clipboard: SyncClipboardSnapshot
    public var preferences: SyncPreferencesSnapshot
    public var tombstones: SyncTombstoneSnapshot
    public var contents: [SyncExportContent]
    public var outboxCutoff: Date
    public var unavailableClipboardRecordNames: Set<String>

    /// 创建 `SyncExportBundle`，保存传入依赖并建立初始状态。
    public init(
        clipboard: SyncClipboardSnapshot,
        preferences: SyncPreferencesSnapshot,
        tombstones: SyncTombstoneSnapshot,
        contents: [SyncExportContent],
        outboxCutoff: Date,
        unavailableClipboardRecordNames: Set<String> = []
    ) {
        self.clipboard = clipboard
        self.preferences = preferences
        self.tombstones = tombstones
        self.contents = contents
        self.outboxCutoff = outboxCutoff
        self.unavailableClipboardRecordNames = unavailableClipboardRecordNames
    }

    /// 计算并返回 `excludingContentIDs` 对应的同步核心领域数据或状态结果。
    public func excludingContentIDs(_ excludedContentIDs: Set<String>) -> Self {
        guard !excludedContentIDs.isEmpty else { return self }
        var filtered = self
        filtered.clipboard.records.removeAll {
            excludedContentIDs.contains($0.contentID)
        }
        filtered.contents.removeAll {
            excludedContentIDs.contains($0.contentID)
        }
        return filtered
    }
}

/// 封装 `SyncPreferenceDomainRecord` 在同步核心领域中的值语义和相关操作。
public struct SyncPreferenceDomainRecord: Codable, Equatable, Sendable {
    public var domain: String
    public var value: Data
    public var clocks: [String: ClipboardFieldClock]
    public var updatedAt: Date

    /// 创建 `SyncPreferenceDomainRecord`，保存传入依赖并建立初始状态。
    public init(domain: String, value: Data, clocks: [String: ClipboardFieldClock], updatedAt: Date) {
        self.domain = domain
        self.value = value
        self.clocks = clocks
        self.updatedAt = updatedAt
    }
}

/// 封装 `SyncPreferencesSnapshot` 在同步核心领域中的值语义和相关操作。
public struct SyncPreferencesSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var domains: [SyncPreferenceDomainRecord]

    /// 创建 `SyncPreferencesSnapshot`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceID: String,
        generation: Int,
        revision: Int64,
        domains: [SyncPreferenceDomainRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.generation = generation
        self.revision = revision
        self.domains = domains
    }
}

/// 封装 `SyncTombstoneRecord` 在同步核心领域中的值语义和相关操作。
public struct SyncTombstoneRecord: Codable, Equatable, Sendable {
    public var tombstoneID: String
    public var targetRecordName: String
    public var targetType: String
    public var generation: Int
    public var deletedAt: Date
    public var reason: String
    public var sourceDeviceID: String
    public var sourceRevision: Int64

    /// 创建 `SyncTombstoneRecord`，保存传入依赖并建立初始状态。
    public init(
        tombstoneID: String,
        targetRecordName: String,
        targetType: String,
        generation: Int,
        deletedAt: Date,
        reason: String,
        sourceDeviceID: String,
        sourceRevision: Int64
    ) {
        self.tombstoneID = tombstoneID
        self.targetRecordName = targetRecordName
        self.targetType = targetType
        self.generation = generation
        self.deletedAt = deletedAt
        self.reason = reason
        self.sourceDeviceID = sourceDeviceID
        self.sourceRevision = sourceRevision
    }
}

/// 封装 `SyncTombstoneSnapshot` 在同步核心领域中的值语义和相关操作。
public struct SyncTombstoneSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var records: [SyncTombstoneRecord]

    /// 创建 `SyncTombstoneSnapshot`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceID: String,
        generation: Int,
        revision: Int64,
        records: [SyncTombstoneRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.generation = generation
        self.revision = revision
        self.records = records
    }
}

/// 描述 `SyncEvictionReason` 在同步核心领域中可取的状态、选项或错误。
public enum SyncEvictionReason: String, Codable, Equatable, Sendable {
    case historyLimit
    case capacityLimit
}

/// 封装 `SyncEvictionRecord` 在同步核心领域中的值语义和相关操作。
public struct SyncEvictionRecord: Codable, Equatable, Sendable {
    public var contentID: String
    public var reason: SyncEvictionReason
    public var deviceID: String
    public var generation: Int
    public var observedRetentionAt: Date
    public var observedFavoriteClock: ClipboardFieldClock
    public var observedPinnedClock: ClipboardFieldClock
    public var evictedAt: Date

    /// 创建 `SyncEvictionRecord`，保存传入依赖并建立初始状态。
    public init(
        contentID: String,
        reason: SyncEvictionReason,
        deviceID: String,
        generation: Int,
        observedRetentionAt: Date,
        observedFavoriteClock: ClipboardFieldClock,
        observedPinnedClock: ClipboardFieldClock,
        evictedAt: Date
    ) {
        self.contentID = contentID
        self.reason = reason
        self.deviceID = deviceID
        self.generation = generation
        self.observedRetentionAt = observedRetentionAt
        self.observedFavoriteClock = observedFavoriteClock
        self.observedPinnedClock = observedPinnedClock
        self.evictedAt = evictedAt
    }

    /// 判断 `isEffective` 所描述的同步核心领域条件是否成立。
    public func isEffective(for candidate: SyncRetentionCandidate) -> Bool {
        guard candidate.contentID == contentID, !candidate.isProtected else { return false }
        guard candidate.retentionAt <= observedRetentionAt else { return false }
        guard !candidate.favoriteClock.wins(over: observedFavoriteClock) else { return false }
        return !candidate.pinnedClock.wins(over: observedPinnedClock)
    }
}

/// 封装 `SyncEvictionSnapshot` 在同步核心领域中的值语义和相关操作。
public struct SyncEvictionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var records: [SyncEvictionRecord]

    /// 创建 `SyncEvictionSnapshot`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceID: String,
        generation: Int,
        records: [SyncEvictionRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.generation = generation
        self.records = records
    }
}

/// 封装 `SyncResetMarker` 在同步核心领域中的值语义和相关操作。
public struct SyncResetMarker: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var resetAt: Date

    /// 创建 `SyncResetMarker`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deviceID: String,
        generation: Int,
        resetAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.generation = generation
        self.resetAt = resetAt
    }
}

/// 封装 `SyncRemovedDeviceMarker` 在同步核心领域中的值语义和相关操作。
public struct SyncRemovedDeviceMarker: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var removedDeviceID: String
    public var removerDeviceID: String
    public var generation: Int
    public var removedAt: Date

    /// 创建 `SyncRemovedDeviceMarker`，保存传入依赖并建立初始状态。
    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        removedDeviceID: String,
        removerDeviceID: String,
        generation: Int,
        removedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.removedDeviceID = removedDeviceID
        self.removerDeviceID = removerDeviceID
        self.generation = generation
        self.removedAt = removedAt
    }
}

/// 描述 `SyncSnapshotCodec` 在同步核心领域中可取的状态、选项或错误。
public enum SyncSnapshotCodec {
    /// 转换 `encode` 接收的同步核心领域数据，并返回规范化结果。
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// 转换 `decode` 接收的同步核心领域数据，并返回规范化结果。
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    /// 计算快照 SHA-256 摘要以检测损坏；该无密钥摘要不验证数据来源。
    public static func digest(_ data: Data) -> String {
        ClipboardContentHasher.sha256String(for: data)
    }
}

/// 封装 `SyncRetentionCandidate` 在同步核心领域中的值语义和相关操作。
public struct SyncRetentionCandidate: Equatable, Sendable {
    public var contentID: String
    public var kind: ClipboardContentKind
    public var byteCount: Int64
    public var createdAt: Date
    public var retentionAt: Date
    public var isFavorite: Bool
    public var isPinned: Bool
    public var favoriteClock: ClipboardFieldClock
    public var pinnedClock: ClipboardFieldClock

    public var isProtected: Bool { isFavorite || isPinned }

    /// 创建 `SyncRetentionCandidate`，保存传入依赖并建立初始状态。
    public init(
        contentID: String,
        kind: ClipboardContentKind,
        byteCount: Int64,
        createdAt: Date,
        retentionAt: Date,
        isFavorite: Bool,
        isPinned: Bool,
        favoriteClock: ClipboardFieldClock = .zero,
        pinnedClock: ClipboardFieldClock = .zero
    ) {
        self.contentID = contentID
        self.kind = kind
        self.byteCount = max(0, byteCount)
        self.createdAt = createdAt
        self.retentionAt = retentionAt
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.favoriteClock = favoriteClock
        self.pinnedClock = pinnedClock
    }

    /// 按照字段时钟或配置优先级计算 `merging` 对应的同步核心领域合并结果。
    public func merging(_ other: SyncRetentionCandidate) -> SyncRetentionCandidate {
        precondition(contentID == other.contentID, "Only identical content IDs can be merged")
        var merged = self
        merged.byteCount = max(byteCount, other.byteCount)
        merged.createdAt = min(createdAt, other.createdAt)
        merged.retentionAt = max(retentionAt, other.retentionAt)
        if other.favoriteClock.shouldReplace(
            currentClock: favoriteClock,
            incomingValue: other.isFavorite,
            currentValue: isFavorite
        ) {
            merged.isFavorite = other.isFavorite
            merged.favoriteClock = other.favoriteClock
        }
        if other.pinnedClock.shouldReplace(
            currentClock: pinnedClock,
            incomingValue: other.isPinned,
            currentValue: isPinned
        ) {
            merged.isPinned = other.isPinned
            merged.pinnedClock = other.pinnedClock
        }
        if other.kind.rawValue < kind.rawValue {
            merged.kind = other.kind
        }
        return merged
    }
}

/// 封装 `SyncRetentionDecision` 在同步核心领域中的值语义和相关操作。
public struct SyncRetentionDecision: Equatable, Sendable {
    public var keptContentIDs: Set<String>
    public var evictions: [SyncEvictionRecord]
    public var totalBytes: Int64
    public var protectedBytes: Int64
    public var ordinaryCount: Int
    public var capacityLimitBytes: Int64
    public var shouldPauseImageUploads: Bool

    /// 创建 `SyncRetentionDecision`，保存传入依赖并建立初始状态。
    public init(
        keptContentIDs: Set<String>,
        evictions: [SyncEvictionRecord],
        totalBytes: Int64,
        protectedBytes: Int64,
        ordinaryCount: Int,
        capacityLimitBytes: Int64,
        shouldPauseImageUploads: Bool
    ) {
        self.keptContentIDs = keptContentIDs
        self.evictions = evictions
        self.totalBytes = totalBytes
        self.protectedBytes = protectedBytes
        self.ordinaryCount = ordinaryCount
        self.capacityLimitBytes = capacityLimitBytes
        self.shouldPauseImageUploads = shouldPauseImageUploads
    }
}

/// 描述 `SyncRetentionPolicy` 在同步核心领域中可取的状态、选项或错误。
public enum SyncRetentionPolicy {
    public static let defaultOrdinaryHistoryLimit = 500
    public static let maximumImageBytes: Int64 = 64 * 1_024 * 1_024

    /// 计算并返回 `mustPauseImageUploads` 对应的同步核心领域数据或状态结果。
    public static func mustPauseImageUploads(
        decision: SyncRetentionDecision,
        currentUsedBytes: Int64,
        newObjectBytes: Int64,
        projectedMetadataBytes: Int64,
        capacityLimitBytes: Int64
    ) -> Bool {
        decision.shouldPauseImageUploads
            || max(0, currentUsedBytes)
                + max(0, newObjectBytes)
                + max(0, projectedMetadataBytes) > max(0, capacityLimitBytes)
    }

    /// 根据输入特征判定 `decide` 对应的同步核心领域分类或处理决策。
    public static func decide(
        candidates: [SyncRetentionCandidate],
        metadataBytes: Int64,
        capacityLimitBytes: Int64 = SyncStorageLimit.default.byteLimit,
        ordinaryHistoryLimit: Int = defaultOrdinaryHistoryLimit,
        generation: Int,
        deviceID: String,
        now: Date
    ) -> SyncRetentionDecision {
        var kept: [String: SyncRetentionCandidate] = [:]
        for candidate in candidates {
            kept[candidate.contentID] = kept[candidate.contentID]?.merging(candidate) ?? candidate
        }
        var totalBytes = max(0, metadataBytes) + kept.values.reduce(Int64(0)) { $0 + $1.byteCount }
        var ordinaryCount = kept.values.lazy.filter { !$0.isProtected }.count
        var evictions: [SyncEvictionRecord] = []

        let ordinaryOldestFirst = kept.values
            .filter { !$0.isProtected }
            .sorted {
                if $0.retentionAt != $1.retentionAt { return $0.retentionAt < $1.retentionAt }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.contentID < $1.contentID
            }

        for candidate in ordinaryOldestFirst {
            let exceedsCount = ordinaryCount > max(0, ordinaryHistoryLimit)
            let exceedsCapacity = totalBytes > max(0, capacityLimitBytes)
            guard exceedsCount || exceedsCapacity else { break }

            kept.removeValue(forKey: candidate.contentID)
            totalBytes -= candidate.byteCount
            ordinaryCount -= 1
            evictions.append(
                SyncEvictionRecord(
                    contentID: candidate.contentID,
                    reason: exceedsCount ? .historyLimit : .capacityLimit,
                    deviceID: deviceID,
                    generation: generation,
                    observedRetentionAt: candidate.retentionAt,
                    observedFavoriteClock: candidate.favoriteClock,
                    observedPinnedClock: candidate.pinnedClock,
                    evictedAt: now
                )
            )
        }

        let protectedBytes = max(0, metadataBytes)
            + kept.values.lazy.filter(\.isProtected).reduce(Int64(0)) { $0 + $1.byteCount }
        let cannotFitAfterOrdinaryEviction = totalBytes > max(0, capacityLimitBytes)

        return SyncRetentionDecision(
            keptContentIDs: Set(kept.keys),
            evictions: evictions,
            totalBytes: totalBytes,
            protectedBytes: protectedBytes,
            ordinaryCount: ordinaryCount,
            capacityLimitBytes: capacityLimitBytes,
            shouldPauseImageUploads: cannotFitAfterOrdinaryEviction || protectedBytes >= max(0, capacityLimitBytes)
        )
    }
}
