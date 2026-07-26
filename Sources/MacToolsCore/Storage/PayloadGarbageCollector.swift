// `PayloadGarbageCollector` 的本地存储领域实现。
// 负责数据库、载荷文件和迁移事务，不管理运行时面板状态。

import GRDB

/// 管理 `PayloadGarbageCollector` 在本地存储领域中的生命周期、依赖和可变状态。
public final class PayloadGarbageCollector: @unchecked Sendable {
    private let database: MacToolsDatabase
    private let payloadStore: PayloadStore

    /// 创建 `PayloadGarbageCollector`，保存传入依赖并建立初始状态。
    public init(database: MacToolsDatabase, payloadStore: PayloadStore) {
        self.database = database
        self.payloadStore = payloadStore
    }

    /// 汇总或整理 `collect` 涉及的本地存储领域数据，并维护容量与保留规则。
    public func collect() throws {
        let pending = try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT gc.payloadID, po.relativePath
                FROM payload_gc_queue AS gc
                JOIN payload_objects AS po ON po.id = gc.payloadID
                ORDER BY gc.enqueuedAt ASC
                """
            ).map { row in
                (payloadID: row["payloadID"] as String, relativePath: row["relativePath"] as String)
            }
        }

        for payload in pending {
            try payloadStore.withExclusiveAccess {
                try database.writer.write { db in
                    let isReferenced = (try Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM clipboard_items WHERE payloadID = ?",
                        arguments: [payload.payloadID]
                    ) ?? 0) > 0
                    if isReferenced {
                        try db.execute(
                            sql: "DELETE FROM payload_gc_queue WHERE payloadID = ?",
                            arguments: [payload.payloadID]
                        )
                        return
                    }

                    do {
                        try payloadStore.remove(relativePath: payload.relativePath)
                        try db.execute(
                            sql: "DELETE FROM payload_objects WHERE id = ?",
                            arguments: [payload.payloadID]
                        )
                    } catch {
                        let errorType = String(reflecting: type(of: error))
                        try db.execute(
                            sql: """
                            UPDATE payload_gc_queue
                            SET attemptCount = attemptCount + 1, lastError = ?
                            WHERE payloadID = ?
                            """,
                            arguments: [errorType, payload.payloadID]
                        )
                    }
                }
            }
        }
    }
}
