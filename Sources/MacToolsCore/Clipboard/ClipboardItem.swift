// `ClipboardItem` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import Foundation

/// 描述 `ClipboardContentKind` 在剪贴板领域中可取的状态、选项或错误。
public enum ClipboardContentKind: String, Codable, Equatable, CaseIterable, Sendable {
    case text
    case url
    case file
    case folder
    case imageFile
    case imageData
    case unknown
}

/// 封装 `ClipboardFieldClock` 在剪贴板领域中的值语义和相关操作。
public struct ClipboardFieldClock: Codable, Equatable, Sendable {
    public var counter: Int64
    public var deviceID: String

    public static let zero = ClipboardFieldClock(counter: 0, deviceID: "")

    /// 创建 `ClipboardFieldClock`，保存传入依赖并建立初始状态。
    public init(counter: Int64, deviceID: String) {
        self.counter = counter
        self.deviceID = deviceID
    }

    /// 按照字段时钟或配置优先级计算 `wins` 对应的剪贴板领域合并结果。
    public func wins(over other: ClipboardFieldClock) -> Bool {
        if counter != other.counter { return counter > other.counter }
        return deviceID > other.deviceID
    }

    /// 对相同时钟采用保守冲突策略：保护状态优先，避免收藏或固定项目
    /// 仅因两个副本共享同一时钟而变为可清理。
    public func shouldReplace(
        currentClock: ClipboardFieldClock,
        incomingValue: Bool,
        currentValue: Bool
    ) -> Bool {
        wins(over: currentClock)
            || (self == currentClock && incomingValue && !currentValue)
    }
}

/// 封装 `ClipboardItem` 在剪贴板领域中的值语义和相关操作。
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

    /// 创建 `ClipboardItem`，保存传入依赖并建立初始状态。
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
