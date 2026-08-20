// `ClipboardItem+FetchableRecord` 的本地存储领域实现。
// 负责数据库、载荷文件和迁移事务，不管理运行时面板状态。

import Foundation
import GRDB

/// 扩展 `ClipboardItem`，补充本文件所需的本地存储领域能力。
extension ClipboardItem: FetchableRecord {
    /// 创建 `ClipboardItem`，保存传入依赖并建立初始状态。
    public init(row: Row) throws {
        let idValue: String = row["id"]
        guard let id = UUID(uuidString: idValue) else {
            throw ClipboardRecordError.invalidUUID(idValue)
        }

        let kindValue: String = row["kind"]
        guard let kind = ClipboardContentKind(rawValue: kindValue) else {
            throw ClipboardRecordError.invalidKind(kindValue)
        }

        self.init(
            id: id,
            kind: kind,
            displayTitle: row["displayTitle"],
            searchableText: row["searchableText"],
            text: row["text"],
            originalPath: row["originalPath"],
            cachedFilePath: row["cachedFilePath"],
            thumbnailPath: nil,
            sourceApp: row["sourceApp"],
            contentHash: row["contentHash"],
            createdAt: row["createdAt"],
            lastUsedAt: row["lastUsedAt"],
            useCount: row["useCount"],
            isPinned: row["isPinned"],
            isFavorite: row["isFavorite"],
            tags: ClipboardTagPolicy.tags(fromStorageValue: row["tagsJSON"]),
            lastCapturedAt: row["lastCapturedAt"],
            retentionAt: row["retentionAt"],
            payloadID: row["payloadID"],
            syncGeneration: row["syncGeneration"],
            favoriteClock: ClipboardFieldClock(
                counter: row["favoriteClock"],
                deviceID: row["favoriteDeviceID"]
            ),
            tagsClock: ClipboardFieldClock(
                counter: row["tagsClock"],
                deviceID: row["tagsDeviceID"]
            ),
            pinnedClock: ClipboardFieldClock(
                counter: row["pinnedClock"],
                deviceID: row["pinnedDeviceID"]
            )
        )
    }
}

/// 描述 `ClipboardRecordError` 在本地存储领域中可取的状态、选项或错误。
enum ClipboardRecordError: Error {
    case invalidUUID(String)
    case invalidKind(String)
}
