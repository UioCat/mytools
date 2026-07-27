// `ClipboardRepository` 的公开结果与同步查询模型。

import Foundation

/// 封装剪贴板写入结果以及清理、去重产生的记录变化。
public struct ClipboardUpsertResult: Equatable {
    public let itemID: UUID
    public let inserted: Bool
    public let prunedItemIDs: [UUID]
    public let duplicateRecordIDs: [UUID]

    public init(
        itemID: UUID,
        inserted: Bool,
        prunedItemIDs: [UUID],
        duplicateRecordIDs: [UUID] = []
    ) {
        self.itemID = itemID
        self.inserted = inserted
        self.prunedItemIDs = prunedItemIDs
        self.duplicateRecordIDs = duplicateRecordIDs
    }
}

/// 同步导出使用的轻量记录，附带本地 payload 元数据但不读取文件内容。
public struct ClipboardSyncCandidate: Sendable {
    public var item: ClipboardItem
    public var payloadByteCount: Int64?

    public init(item: ClipboardItem, payloadByteCount: Int64?) {
        self.item = item
        self.payloadByteCount = payloadByteCount
    }
}
