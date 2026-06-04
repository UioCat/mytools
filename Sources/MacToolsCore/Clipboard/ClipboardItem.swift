import Foundation

public enum ClipboardContentKind: String, Codable, Equatable, CaseIterable {
    case text
    case url
    case file
    case folder
    case imageFile
    case imageData
    case unknown
}

public struct ClipboardItem: Codable, Equatable, Identifiable {
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
    public var lastUsedAt: Date?
    public var useCount: Int
    public var isPinned: Bool
    public var isFavorite: Bool

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
        isFavorite: Bool
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
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.isPinned = isPinned
        self.isFavorite = isFavorite
    }
}
