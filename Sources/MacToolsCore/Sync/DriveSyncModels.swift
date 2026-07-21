import Foundation

public enum SyncRecordType: String, Codable, Equatable, Sendable {
    case clipboardContent
    case preferenceDomain
    case tombstone
    case deviceReplica
}

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

public struct SyncProtocolDescriptor: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var protocolVersion: Int
    public var storeID: UUID
    public var createdAt: Date
    public var capacityLimit: SyncStorageLimit

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

public struct SyncSnapshotDigests: Codable, Equatable, Sendable {
    public var clipboard: String
    public var preferences: String
    public var tombstones: String

    public init(clipboard: String, preferences: String, tombstones: String) {
        self.clipboard = clipboard
        self.preferences = preferences
        self.tombstones = tombstones
    }
}

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

public struct SyncDeviceSummary: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isCurrentDevice: Bool
    public var lastUpdatedAt: Date?

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
    public var favoriteClock: ClipboardFieldClock
    public var pinnedClock: ClipboardFieldClock

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
        favoriteClock: ClipboardFieldClock,
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
        self.favoriteClock = favoriteClock
        self.pinnedClock = pinnedClock
    }
}

public struct SyncClipboardSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var records: [SyncClipboardRecord]

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

public struct SyncTextContentObject: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var contentID: String
    public var kind: ClipboardContentKind
    public var text: String
    public var byteCount: Int64

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

public struct SyncExportContent: Equatable, Sendable {
    public var contentID: String
    public var kind: ClipboardContentKind
    public var data: Data

    public init(contentID: String, kind: ClipboardContentKind, data: Data) {
        self.contentID = contentID
        self.kind = kind
        self.data = data
    }
}

public struct SyncExportBundle: Equatable, Sendable {
    public var clipboard: SyncClipboardSnapshot
    public var preferences: SyncPreferencesSnapshot
    public var tombstones: SyncTombstoneSnapshot
    public var contents: [SyncExportContent]
    public var outboxCutoff: Date
    public var unavailableClipboardRecordNames: Set<String>

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
}

public struct SyncPreferenceDomainRecord: Codable, Equatable, Sendable {
    public var domain: String
    public var value: Data
    public var clocks: [String: ClipboardFieldClock]
    public var updatedAt: Date

    public init(domain: String, value: Data, clocks: [String: ClipboardFieldClock], updatedAt: Date) {
        self.domain = domain
        self.value = value
        self.clocks = clocks
        self.updatedAt = updatedAt
    }
}

public struct SyncPreferencesSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var domains: [SyncPreferenceDomainRecord]

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

public struct SyncTombstoneRecord: Codable, Equatable, Sendable {
    public var tombstoneID: String
    public var targetRecordName: String
    public var targetType: String
    public var generation: Int
    public var deletedAt: Date
    public var reason: String
    public var sourceDeviceID: String
    public var sourceRevision: Int64

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

public struct SyncTombstoneSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var revision: Int64
    public var records: [SyncTombstoneRecord]

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

public enum SyncEvictionReason: String, Codable, Equatable, Sendable {
    case historyLimit
    case capacityLimit
}

public struct SyncEvictionRecord: Codable, Equatable, Sendable {
    public var contentID: String
    public var reason: SyncEvictionReason
    public var deviceID: String
    public var generation: Int
    public var observedRetentionAt: Date
    public var observedFavoriteClock: ClipboardFieldClock
    public var observedPinnedClock: ClipboardFieldClock
    public var evictedAt: Date

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

    public func isEffective(for candidate: SyncRetentionCandidate) -> Bool {
        guard candidate.contentID == contentID, !candidate.isProtected else { return false }
        guard candidate.retentionAt <= observedRetentionAt else { return false }
        guard !candidate.favoriteClock.wins(over: observedFavoriteClock) else { return false }
        return !candidate.pinnedClock.wins(over: observedPinnedClock)
    }
}

public struct SyncEvictionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var records: [SyncEvictionRecord]

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

public struct SyncResetMarker: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var deviceID: String
    public var generation: Int
    public var resetAt: Date

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

public struct SyncRemovedDeviceMarker: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var removedDeviceID: String
    public var removerDeviceID: String
    public var generation: Int
    public var removedAt: Date

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

public enum SyncSnapshotCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    public static func digest(_ data: Data) -> String {
        ClipboardContentHasher.sha256String(for: data)
    }
}

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

public struct SyncRetentionDecision: Equatable, Sendable {
    public var keptContentIDs: Set<String>
    public var evictions: [SyncEvictionRecord]
    public var totalBytes: Int64
    public var protectedBytes: Int64
    public var ordinaryCount: Int
    public var capacityLimitBytes: Int64
    public var shouldPauseImageUploads: Bool

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

public enum SyncRetentionPolicy {
    public static let defaultOrdinaryHistoryLimit = 500
    public static let maximumImageBytes: Int64 = 64 * 1_024 * 1_024

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
