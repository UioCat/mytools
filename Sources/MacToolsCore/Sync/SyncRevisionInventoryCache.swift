import Foundation

/// 不可变 revision 的容量索引；只缓存容量，不参与副本校验或删除判断。
public final class SyncRevisionInventoryCache: @unchecked Sendable {
    private struct Entry {
        var modifiedAt: Date?
        var createdAt: Date?
        var identity: String
        var bytes: Int64
        var checkedAt: Date
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]

    public init() {}

    /// 协议使用原子目录发布；替换、增删文件或定期审计都会重新统计。
    func bytes(
        at url: URL,
        values: URLResourceValues,
        now: Date = Date(),
        measure: () throws -> Int64
    ) rethrows -> Int64 {
        let identity = String(describing: values.fileResourceIdentifier)
        lock.lock()
        let entry = entries[url]
        lock.unlock()
        if let entry,
           entry.modifiedAt == values.contentModificationDate,
           entry.createdAt == values.creationDate,
           entry.identity == identity,
           now.timeIntervalSince(entry.checkedAt) >= 0,
           now.timeIntervalSince(entry.checkedAt) < 30 * 60 {
            return entry.bytes
        }
        let bytes = try measure()
        lock.lock()
        entries[url] = Entry(
            modifiedAt: values.contentModificationDate,
            createdAt: values.creationDate,
            identity: identity,
            bytes: bytes,
            checkedAt: now
        )
        lock.unlock()
        return bytes
    }

    func retain(_ urls: Set<URL>) {
        lock.lock()
        entries = entries.filter { urls.contains($0.key) }
        lock.unlock()
    }
}
