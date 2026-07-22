import Foundation

public enum ClipboardContentKind: String, Codable, Equatable, CaseIterable, Sendable {
    case text
    case url
    case file
    case folder
    case imageFile
    case imageData
    case unknown
}

public struct ClipboardFieldClock: Codable, Equatable, Sendable {
    public var counter: Int64
    public var deviceID: String

    public static let zero = ClipboardFieldClock(counter: 0, deviceID: "")

    public init(counter: Int64, deviceID: String) {
        self.counter = counter
        self.deviceID = deviceID
    }

    public func wins(over other: ClipboardFieldClock) -> Bool {
        if counter != other.counter { return counter > other.counter }
        return deviceID > other.deviceID
    }

    /// Resolves equal clocks conservatively: protection wins so a favorite or
    /// pinned item cannot become evictable because two replicas share a clock.
    public func shouldReplace(
        currentClock: ClipboardFieldClock,
        incomingValue: Bool,
        currentValue: Bool
    ) -> Bool {
        wins(over: currentClock)
            || (self == currentClock && incomingValue && !currentValue)
    }
}

public struct ClipboardItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ClipboardContentKind
    public var displayTitle: String
    public var searchableText: String
    public var text: String?
    public var originalPath: String?
    public var cachedFilePath: String?
    public var thumbnailPath: String?
    public var sourceApp: String?
    public var contentHash: String?
    public var createdAt: Date
    public var lastCapturedAt: Date
    public var lastUsedAt: Date?
    public var retentionAt: Date
    public var useCount: Int
    public var isPinned: Bool
    public var isFavorite: Bool
    public var payloadID: String?
    public var syncGeneration: Int
    public var favoriteClock: ClipboardFieldClock
    public var pinnedClock: ClipboardFieldClock

    public init(
        id: UUID,
        kind: ClipboardContentKind,
        displayTitle: String,
        searchableText: String,
        text: String?,
        originalPath: String?,
        cachedFilePath: String?,
        thumbnailPath: String?,
        sourceApp: String?,
        contentHash: String? = nil,
        createdAt: Date,
        lastUsedAt: Date?,
        useCount: Int,
        isPinned: Bool,
        isFavorite: Bool,
        lastCapturedAt: Date? = nil,
        retentionAt: Date? = nil,
        payloadID: String? = nil,
        syncGeneration: Int = 1,
        favoriteClock: ClipboardFieldClock = .zero,
        pinnedClock: ClipboardFieldClock = .zero
    ) {
        self.id = id
        self.kind = kind
        self.displayTitle = displayTitle
        self.searchableText = searchableText
        self.text = text
        self.originalPath = originalPath
        self.cachedFilePath = cachedFilePath
        self.thumbnailPath = thumbnailPath
        self.sourceApp = sourceApp
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.lastCapturedAt = lastCapturedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
        self.retentionAt = retentionAt ?? max(lastCapturedAt ?? createdAt, lastUsedAt ?? .distantPast)
        self.useCount = useCount
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.payloadID = payloadID
        self.syncGeneration = syncGeneration
        self.favoriteClock = favoriteClock
        self.pinnedClock = pinnedClock
    }
}
