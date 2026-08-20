import Foundation
import GRDB

extension ClipboardRepository {
    /// 更新收藏值和逻辑时钟，并在需要时重新裁剪普通历史与发布同步变更。
    public func setFavorite(id: UUID, isFavorite: Bool, historyLimit: Int? = nil) throws {
        try database.writer.write { db in
            let deviceID = try self.deviceID(in: db)
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET isFavorite = ?, favoriteClock = favoriteClock + 1, favoriteDeviceID = ?
                WHERE id = ?
                """,
                arguments: [isFavorite, deviceID, id.uuidString]
            )
            if !isFavorite, let historyLimit {
                _ = try pruneNormalHistory(in: db, limit: historyLimit)
            }
            try enqueueSyncChangeIfSyncable(recordName: id.uuidString, operation: "save", in: db)
        }
        collectPayloadGarbageAfterCommit()
    }

    /// 更新收藏标签集合和逻辑时钟，并把字段变化写入同步 outbox。
    public func setTags(id: UUID, tags: [String]) throws {
        let tagsJSON = try ClipboardTagPolicy.storageValue(for: tags)
        try database.writer.write { db in
            let deviceID = try self.deviceID(in: db)
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET tagsJSON = ?, tagsClock = tagsClock + 1, tagsDeviceID = ?
                WHERE id = ?
                """,
                arguments: [tagsJSON, deviceID, id.uuidString]
            )
            try enqueueSyncChangeIfSyncable(recordName: id.uuidString, operation: "save", in: db)
        }
    }

    /// 更新置顶值和逻辑时钟，并把字段变化写入本机副本与同步 outbox。
    public func setPinned(id: UUID, isPinned: Bool, historyLimit: Int? = nil) throws {
        try database.writer.write { db in
            let deviceID = try self.deviceID(in: db)
            try db.execute(
                sql: """
                UPDATE clipboard_items
                SET isPinned = ?, pinnedClock = pinnedClock + 1, pinnedDeviceID = ?
                WHERE id = ?
                """,
                arguments: [isPinned, deviceID, id.uuidString]
            )
            if !isPinned, let historyLimit {
                _ = try pruneNormalHistory(in: db, limit: historyLimit)
            }
            try enqueueSyncChangeIfSyncable(recordName: id.uuidString, operation: "save", in: db)
        }
        collectPayloadGarbageAfterCommit()
    }
}
