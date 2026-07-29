// `ClipboardRepository` 的公开结果与同步查询模型。

import Foundation

/// 封装剪贴板写入结果以及清理、去重产生的记录变化。
public struct ClipboardUpsertResult: Equatable {
    public let itemID: UUID
    public let inserted: Bool
    public let prunedItemIDs: [UUID]
    public let duplicateRecordIDs: [UUID]

    /// 汇总一次 upsert 的最终记录、插入状态以及需要清理的历史或重复记录。
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

    /// 建立同步候选；payload 字节数为空表示记录没有外部载荷元数据。
    public init(item: ClipboardItem, payloadByteCount: Int64?) {
        self.item = item
        self.payloadByteCount = payloadByteCount
    }
}
