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

/// 统一剪贴板收藏标签的长度、数量、去重和比较规则。
public enum ClipboardTagPolicy {
    public static let maximumTagCount = 8
    public static let maximumNameLength = 24

    /// 生成跨设备稳定的标签比较键，用于去重、筛选和排序。
    public static func comparisonKey(for tag: String) -> String {
        tag.precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// 清理标签集合并限制单条收藏可持有的标签数量。
    public static func normalized(_ tags: [String]) -> [String] {
        Array(normalizedCatalog(tags).prefix(maximumTagCount))
    }

    /// 清理全局可复用标签目录；目录不受单条收藏的数量上限影响。
    public static func normalizedCatalog(_ tags: [String]) -> [String] {
        var namesByKey: [String: String] = [:]
        for rawTag in tags {
            let trimmed = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(trimmed.prefix(maximumNameLength))
                .precomposedStringWithCanonicalMapping
            guard !name.isEmpty else { continue }
            let key = comparisonKey(for: name)
            if namesByKey[key] == nil {
                namesByKey[key] = name
            }
        }

        return namesByKey
            .sorted { lhs, rhs in
                lhs.key == rhs.key ? lhs.value < rhs.value : lhs.key < rhs.key
            }
            .map(\.value)
    }

    /// 判断标签集合是否包含指定名称，匹配时忽略大小写和 Unicode 组合形式。
    public static func contains(_ tag: String, in tags: [String]) -> Bool {
        let key = comparisonKey(for: tag.trimmingCharacters(in: .whitespacesAndNewlines))
        return tags.contains { comparisonKey(for: $0) == key }
    }

    /// 将规范化标签编码为 SQLite 文本字段。
    static func storageValue(for tags: [String]) throws -> String {
        String(decoding: try JSONEncoder().encode(normalized(tags)), as: UTF8.self)
    }

    /// 从 SQLite 文本字段恢复标签；损坏内容按空集合回退，避免整条记录不可读取。
    static func tags(fromStorageValue value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return normalized(tags)
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
    public var tags: [String]
    public var payloadID: String?
    public var syncGeneration: Int
    public var favoriteClock: ClipboardFieldClock
    public var tagsClock: ClipboardFieldClock
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
        tags: [String] = [],
        lastCapturedAt: Date? = nil,
        retentionAt: Date? = nil,
        payloadID: String? = nil,
        syncGeneration: Int = 1,
        favoriteClock: ClipboardFieldClock = .zero,
        tagsClock: ClipboardFieldClock = .zero,
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
        self.tags = ClipboardTagPolicy.normalized(tags)
        self.payloadID = payloadID
        self.syncGeneration = syncGeneration
        self.favoriteClock = favoriteClock
        self.tagsClock = tagsClock
        self.pinnedClock = pinnedClock
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayTitle, searchableText, text, originalPath
        case cachedFilePath, thumbnailPath, sourceApp, contentHash, createdAt
        case lastCapturedAt, lastUsedAt, retentionAt, useCount, isPinned, isFavorite
        case tags, payloadID, syncGeneration, favoriteClock, tagsClock, pinnedClock
    }

    /// 解码领域记录；旧编码缺少标签字段时使用空集合和零时钟。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(ClipboardContentKind.self, forKey: .kind),
            displayTitle: try container.decode(String.self, forKey: .displayTitle),
            searchableText: try container.decode(String.self, forKey: .searchableText),
            text: try container.decodeIfPresent(String.self, forKey: .text),
            originalPath: try container.decodeIfPresent(String.self, forKey: .originalPath),
            cachedFilePath: try container.decodeIfPresent(String.self, forKey: .cachedFilePath),
            thumbnailPath: try container.decodeIfPresent(String.self, forKey: .thumbnailPath),
            sourceApp: try container.decodeIfPresent(String.self, forKey: .sourceApp),
            contentHash: try container.decodeIfPresent(String.self, forKey: .contentHash),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            lastUsedAt: try container.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            useCount: try container.decode(Int.self, forKey: .useCount),
            isPinned: try container.decode(Bool.self, forKey: .isPinned),
            isFavorite: try container.decode(Bool.self, forKey: .isFavorite),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            lastCapturedAt: try container.decode(Date.self, forKey: .lastCapturedAt),
            retentionAt: try container.decode(Date.self, forKey: .retentionAt),
            payloadID: try container.decodeIfPresent(String.self, forKey: .payloadID),
            syncGeneration: try container.decode(Int.self, forKey: .syncGeneration),
            favoriteClock: try container.decode(ClipboardFieldClock.self, forKey: .favoriteClock),
            tagsClock: try container.decodeIfPresent(
                ClipboardFieldClock.self,
                forKey: .tagsClock
            ) ?? .zero,
            pinnedClock: try container.decode(ClipboardFieldClock.self, forKey: .pinnedClock)
        )
    }

    /// 编码完整领域记录，标签在写出前再次规范化。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(searchableText, forKey: .searchableText)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(originalPath, forKey: .originalPath)
        try container.encodeIfPresent(cachedFilePath, forKey: .cachedFilePath)
        try container.encodeIfPresent(thumbnailPath, forKey: .thumbnailPath)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encodeIfPresent(contentHash, forKey: .contentHash)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastCapturedAt, forKey: .lastCapturedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(retentionAt, forKey: .retentionAt)
        try container.encode(useCount, forKey: .useCount)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(ClipboardTagPolicy.normalized(tags), forKey: .tags)
        try container.encodeIfPresent(payloadID, forKey: .payloadID)
        try container.encode(syncGeneration, forKey: .syncGeneration)
        try container.encode(favoriteClock, forKey: .favoriteClock)
        try container.encode(tagsClock, forKey: .tagsClock)
        try container.encode(pinnedClock, forKey: .pinnedClock)
    }
}
