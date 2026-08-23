// 同一同步根目录在一台 Mac 上只允许一个进程执行完整写周期。

import Darwin
import Foundation
import MacToolsCore

final class SyncStoreProcessLock: @unchecked Sendable {
    func withLock<Value>(
        for rootURL: URL,
        operation: () throws -> Value
    ) throws -> Value? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.mactools.sync-locks", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let rootIdentity = Data(rootURL.standardizedFileURL.path.utf8)
        let lockURL = directory
            .appendingPathComponent(SyncSnapshotCodec.digest(rootIdentity))
            .appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
