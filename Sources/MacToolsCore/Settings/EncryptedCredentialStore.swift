// `EncryptedCredentialStore` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import Darwin
import Foundation

/// 描述 `EncryptedCredentialStoreError` 在设置与凭据领域中可取的状态、选项或错误。
public enum EncryptedCredentialStoreError: Error, Equatable, Sendable {
    case unsupportedMigrationMarker(String)
    case fileVerificationFailed
    case atomicReplaceFailed(Int32)
}

/// 在进程锁内原子读写本地凭据信封，并维护一次性迁移完成标记。
public final class EncryptedCredentialStore: @unchecked Sendable {
    public static let currentMigrationVersion = 1

    private let envelopeURL: URL
    private let migrationMarkerURL: URL
    private let fileManager: FileManager
    private let codec: CredentialEnvelopeCodec
    private let lock = NSLock()

    /// 创建 `EncryptedCredentialStore`，保存传入依赖并建立初始状态。
    public init(
        envelopeURL: URL,
        migrationMarkerURL: URL,
        fileManager: FileManager = .default,
        codec: CredentialEnvelopeCodec = CredentialEnvelopeCodec()
    ) {
        self.envelopeURL = envelopeURL.standardizedFileURL
        self.migrationMarkerURL = migrationMarkerURL.standardizedFileURL
        self.fileManager = fileManager
        self.codec = codec
    }

    /// 在进程锁内读取并验证指定凭据的本地加密信封。
    public func readEnvelope(for credential: CredentialKey) throws -> CredentialEnvelope? {
        try withLock {
            try readEnvelopeUnlocked(for: credential)
        }
    }

    /// 读取、认证并解密本地凭据记录；文件不存在时返回 nil。
    public func readRecord(for credential: CredentialKey) throws -> CredentialEnvelopeRecord? {
        try withLock {
            guard let envelope = try readEnvelopeUnlocked(for: credential) else { return nil }
            return try codec.open(envelope, for: credential)
        }
    }

    /// 先验证信封可由指定凭据打开，再通过原子替换持久化并回读确认。
    public func write(
        _ envelope: CredentialEnvelope,
        for credential: CredentialKey
    ) throws {
        try withLock {
            try writeUnlocked(envelope, for: credential)
        }
    }

    /// 基于本地和远端最低计数生成下一逻辑时钟，密封后原子替换本地信封。
    public func update(
        value: String?,
        for credential: CredentialKey,
        deviceID: String,
        minimumCounter: Int64 = 0,
        updatedAt: Date = Date()
    ) throws -> CredentialReconciliationWinner {
        try withLock {
            let current = try readEnvelopeUnlocked(for: credential).map {
                try codec.open($0, for: credential)
            }
            // 当前协议直接对最大计数加一，尚未对恶意 Int64.max 输入提供上界保护。
            let nextCounter = max(current?.clock.counter ?? 0, minimumCounter) + 1
            let envelope = try codec.seal(
                value: value,
                for: credential,
                clock: ClipboardFieldClock(
                    counter: nextCounter,
                    deviceID: deviceID
                ),
                updatedAt: updatedAt
            )
            try writeUnlocked(envelope, for: credential)
            return CredentialReconciliationWinner(
                envelope: envelope,
                record: try codec.open(envelope, for: credential)
            )
        }
    }

    /// 在本地信封与云端副本中选择获胜版本，并在需要时回写本地缓存。
    public func reconcile(
        replicas: [CredentialReplica],
        for credential: CredentialKey
    ) throws -> CredentialReconciliationWinner? {
        try withLock {
            let local: CredentialEnvelope?
            do {
                local = try readEnvelopeUnlocked(for: credential)
            } catch let error as CredentialEnvelopeCodecError {
                switch error {
                case .unsupportedSchema, .unsupportedKeyVersion:
                    throw error
                default:
                    // 只有存在可用远端副本时才允许跳过损坏本地信封；否则保留原错误供用户处理。
                    guard !replicas.isEmpty else { throw error }
                    local = nil
                }
            } catch {
                guard !replicas.isEmpty else { throw error }
                local = nil
            }
            let winner = try CredentialReconciler(codec: codec).winner(
                local: local,
                replicas: replicas,
                for: credential
            )
            if let winner, winner.envelope != local {
                try writeUnlocked(winner.envelope, for: credential)
            }
            return winner
        }
    }

    /// 校验迁移标记权限和版本；未知版本作为不兼容状态抛错。
    public func isMigrationComplete() throws -> Bool {
        try withLock {
            guard fileManager.fileExists(atPath: migrationMarkerURL.path) else {
                return false
            }
            try applyFilePermissions(at: migrationMarkerURL)
            let marker = try String(
                contentsOf: migrationMarkerURL,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard marker == String(Self.currentMigrationVersion) else {
                throw EncryptedCredentialStoreError.unsupportedMigrationMarker(marker)
            }
            return true
        }
    }

    /// 提交 `markMigrationComplete` 对应的设置与凭据领域状态，并记录后续流程所需的进度。
    public func markMigrationComplete() throws {
        try withLock {
            let data = Data("\(Self.currentMigrationVersion)\n".utf8)
            try verifiedAtomicWrite(data, to: migrationMarkerURL)
            guard try Data(contentsOf: migrationMarkerURL) == data else {
                throw EncryptedCredentialStoreError.fileVerificationFailed
            }
        }
    }

    /// 在调用方已持锁时读取并认证信封，同时修复目标文件权限。
    private func readEnvelopeUnlocked(
        for credential: CredentialKey
    ) throws -> CredentialEnvelope? {
        guard fileManager.fileExists(atPath: envelopeURL.path) else { return nil }
        try applyFilePermissions(at: envelopeURL)
        let envelope = try codec.decode(Data(contentsOf: envelopeURL, options: [.mappedIfSafe]))
        _ = try codec.open(envelope, for: credential)
        return envelope
    }

    /// 在调用方已持锁时验证、编码、原子写入并回读信封。
    private func writeUnlocked(
        _ envelope: CredentialEnvelope,
        for credential: CredentialKey
    ) throws {
        _ = try codec.open(envelope, for: credential)
        let data = try codec.encode(envelope)
        try verifiedAtomicWrite(data, to: envelopeURL)
        guard try readEnvelopeUnlocked(for: credential) == envelope else {
            throw EncryptedCredentialStoreError.fileVerificationFailed
        }
    }

    /// 以 0600 staging 文件完成写后校验，再通过 rename 原子替换目标文件。
    private func verifiedAtomicWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let stagingURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }
        try data.write(to: stagingURL, options: [.atomic])
        try applyFilePermissions(at: stagingURL)
        guard try Data(contentsOf: stagingURL) == data else {
            throw EncryptedCredentialStoreError.fileVerificationFailed
        }

        let result = stagingURL.withUnsafeFileSystemRepresentation { sourcePath in
            url.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw EncryptedCredentialStoreError.atomicReplaceFailed(errno)
        }
        try applyFilePermissions(at: url)
        guard try Data(contentsOf: url) == data else {
            throw EncryptedCredentialStoreError.fileVerificationFailed
        }
    }

    /// 将凭据信封、staging 文件或迁移标记权限收紧为仅当前用户可读写。
    private func applyFilePermissions(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    /// 在锁保护范围内执行传入操作，并返回操作结果。
    private func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
