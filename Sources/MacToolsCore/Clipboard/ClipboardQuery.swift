import Foundation

/// 全库查询条件；展示层只传递值，不接触仓储。
public struct ClipboardQuery: Equatable, Sendable {
    public enum Category: Sendable { case all, text, images, favorites }
    public var text: String
    public var category: Category
    public var tag: String?

    public init(text: String = "", category: Category = .all, tag: String? = nil) {
        self.text = text
        self.category = category
        self.tag = tag
    }
}

public struct ClipboardTagSummary: Equatable, Sendable {
    public let name: String
    public let count: Int
    public init(name: String, count: Int) { self.name = name; self.count = count }
}

/// 独立于分页结果的全库目录。
public struct ClipboardCatalog: Equatable, Sendable {
    public var favoriteCount: Int
    public var hasClearableItems: Bool
    public var tags: [ClipboardTagSummary]
    public init(favoriteCount: Int = 0, hasClearableItems: Bool = false, tags: [ClipboardTagSummary] = []) {
        self.favoriteCount = favoriteCount
        self.hasClearableItems = hasClearableItems
        self.tags = tags
    }
}
