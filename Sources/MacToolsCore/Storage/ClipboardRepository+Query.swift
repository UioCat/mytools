// 全库筛选、分页和目录统计。
import Foundation
import GRDB

extension ClipboardRepository {
    /// 解析并返回 `search` 对应的本地存储领域结果。
    public func search(_ query: String, limit: Int) throws -> [ClipboardItem] {
        try search(query, limit: limit, favoritesOnly: false)
    }

    /// 解析并返回 `search` 对应的本地存储领域结果。
    public func search(_ query: String, limit: Int, favoritesOnly: Bool) throws -> [ClipboardItem] {
        try queryPage(ClipboardQuery(text: query, category: favoritesOnly ? .favorites : .all), limit: limit)
    }
    /// 全库先筛选再分页，与面板的 Unicode、标签和分类规则保持一致。
    public func queryPage(_ query: ClipboardQuery, limit: Int, offset: Int = 0) throws -> [ClipboardItem] {
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadRootPath = payloadStore?.rootDirectory.path
        return try database.writer.read { db in
            db.add(function: DatabaseFunction("clipboard_contains", argumentCount: 2, pure: true) { values in
                guard let haystack = String.fromDatabaseValue(values[0]),
                      let needle = String.fromDatabaseValue(values[1]) else { return false }
                return haystack.localizedCaseInsensitiveContains(needle)
            })
            db.add(function: DatabaseFunction("clipboard_tag_matches", argumentCount: 3, pure: true) { values in
                let tags = ClipboardTagPolicy.tags(fromStorageValue: String.fromDatabaseValue(values[0]) ?? "[]")
                let text = String.fromDatabaseValue(values[1]) ?? ""
                let exact = Bool.fromDatabaseValue(values[2]) ?? false
                return exact ? ClipboardTagPolicy.contains(text, in: tags)
                    : tags.contains { $0.localizedCaseInsensitiveContains(text) }
            })
            var clauses = ["1 = 1"]
            var arguments = StatementArguments([payloadRootPath, payloadRootPath])
            switch query.category {
            case .all: break
            case .text: clauses.append("ci.kind IN ('text', 'url')")
            case .images: clauses.append("ci.kind IN ('imageData', 'imageFile')")
            case .favorites: clauses.append("ci.isFavorite = 1")
            }
            if query.category == .favorites, let tag = query.tag {
                clauses.append("clipboard_tag_matches(ci.tagsJSON, ?, 1)")
                arguments += StatementArguments([tag])
            }
            if !text.isEmpty {
                let tagClause = query.category == .favorites ? " OR clipboard_tag_matches(ci.tagsJSON, ?, 0)" : ""
                clauses.append("(clipboard_contains(ci.displayTitle, ?) OR clipboard_contains(ci.searchableText, ?)\(tagClause))")
                arguments += StatementArguments([text, text])
                if query.category == .favorites { arguments += StatementArguments([text]) }
            }
            arguments += StatementArguments([max(0, limit), max(0, offset)])
            return try ClipboardItem.fetchAll(db, sql: """
                \(Self.selectClipboardItemsSQL)
                WHERE \(clauses.joined(separator: " AND "))
                ORDER BY ci.isPinned DESC, ci.lastCapturedAt DESC, ci.createdAt DESC, ci.id ASC
                LIMIT ? OFFSET ?
                """, arguments: arguments)
        }
    }

    /// 目录独立于当前筛选和分页，仅读取收藏标签和计数。
    public func catalog() throws -> ClipboardCatalog {
        try database.writer.read { db in
            let favoriteCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_items WHERE isFavorite = 1") ?? 0
            let hasClearableItems = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM clipboard_items WHERE isFavorite = 0)") ?? false
            let values = try String.fetchAll(db, sql: "SELECT tagsJSON FROM clipboard_items WHERE isFavorite = 1 ORDER BY id")
            var names: [String: String] = [:]
            var counts: [String: Int] = [:]
            for value in values {
                for tag in ClipboardTagPolicy.normalized(ClipboardTagPolicy.tags(fromStorageValue: value)) {
                    let key = ClipboardTagPolicy.comparisonKey(for: tag)
                    names[key] = names[key] ?? tag
                    counts[key, default: 0] += 1
                }
            }
            return ClipboardCatalog(favoriteCount: favoriteCount, hasClearableItems: hasClearableItems,
                tags: names.keys.sorted().map { ClipboardTagSummary(name: names[$0]!, count: counts[$0]!) })
        }
    }
}
