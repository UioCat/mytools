import GRDB

public final class PayloadGarbageCollector: @unchecked Sendable {
    private let database: MacToolsDatabase
    private let payloadStore: PayloadStore

    public init(database: MacToolsDatabase, payloadStore: PayloadStore) {
        self.database = database
        self.payloadStore = payloadStore
    }

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
