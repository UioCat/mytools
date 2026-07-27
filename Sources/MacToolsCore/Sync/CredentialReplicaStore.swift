// `CredentialReplicaStore` 的同步核心领域实现。
// 负责协议模型、合并、对象存储和凭据对账，不管理 AppKit 生命周期。

import Foundation

/// 描述 `CredentialReplicaStoreError` 在同步核心领域中可取的状态、选项或错误。
public enum CredentialReplicaStoreError: Error, Equatable, Sendable {
    case invalidDeviceID(String)
    case itemNotDownloaded(URL)
    case fileConflict(URL)
    case unreadableReplica(String)
    case fileVerificationFailed
}

/// 封装 `CredentialReplica` 在同步核心领域中的值语义和相关操作。
public struct CredentialReplica: Equatable, Sendable {
    public var deviceID: String
    public var envelope: CredentialEnvelope

    /// 创建 `CredentialReplica`，保存传入依赖并建立初始状态。
    public init(deviceID: String, envelope: CredentialEnvelope) {
        self.deviceID = deviceID
        self.envelope = envelope
    }
}

/// 封装 `CredentialReplicaFailure` 在同步核心领域中的值语义和相关操作。
public struct CredentialReplicaFailure: Equatable, Sendable {
    public var deviceID: String
    public var error: CredentialReplicaStoreError

    /// 创建 `CredentialReplicaFailure`，保存传入依赖并建立初始状态。
    public init(deviceID: String, error: CredentialReplicaStoreError) {
        self.deviceID = deviceID
        self.error = error
    }
}

/// 封装 `CredentialReplicaScan` 在同步核心领域中的值语义和相关操作。
public struct CredentialReplicaScan: Equatable, Sendable {
    public var replicas: [CredentialReplica]
    public var failures: [CredentialReplicaFailure]

    /// 创建 `CredentialReplicaScan`，保存传入依赖并建立初始状态。
    public init(
        replicas: [CredentialReplica],
        failures: [CredentialReplicaFailure]
    ) {
        self.replicas = replicas
        self.failures = failures
    }
}

/// 读写每台设备独立的 iCloud 凭据副本，并区分未下载、冲突和损坏状态。
public final class CredentialReplicaStore: @unchecked Sendable {
    private static let fileSuffix = ".v1.json"

    public let rootURL: URL
    private let fileManager: FileManager
    private let codec: CredentialEnvelopeCodec

    /// 创建 `CredentialReplicaStore`，保存传入依赖并建立初始状态。
    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        codec: CredentialEnvelopeCodec = CredentialEnvelopeCodec()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.codec = codec
    }

    /// 扫描未移除设备的副本，保留单文件失败以便其他有效副本继续参与对账。
    public func scan(excluding removedDeviceIDs: Set<String>) throws -> CredentialReplicaScan {
        guard fileManager.fileExists(atPath: replicasURL.path) else {
            return CredentialReplicaScan(replicas: [], failures: [])
        }
        let files = try fileManager.contentsOfDirectory(
            at: replicasURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter {
            $0.lastPathComponent.hasSuffix(Self.fileSuffix)
        }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        var replicas: [CredentialReplica] = []
        var failures: [CredentialReplicaFailure] = []
        for url in files {
            let fileName = url.lastPathComponent
            let deviceID = String(fileName.dropLast(Self.fileSuffix.count))
            guard UUID(uuidString: deviceID) != nil else {
                failures.append(
                    CredentialReplicaFailure(
                        deviceID: deviceID,
                        error: .invalidDeviceID(deviceID)
                    )
                )
                continue
            }
            guard !removedDeviceIDs.contains(deviceID) else { continue }
            do {
                let envelope = try codec.decode(readData(at: url))
                _ = try codec.open(envelope, for: .bailianAPIKey)
                replicas.append(
                    CredentialReplica(deviceID: deviceID, envelope: envelope)
                )
            } catch let error as CredentialReplicaStoreError {
                failures.append(
                    CredentialReplicaFailure(deviceID: deviceID, error: error)
                )
            } catch {
                failures.append(
                    CredentialReplicaFailure(
                        deviceID: deviceID,
                        error: .unreadableReplica(deviceID)
                    )
                )
            }
        }
        return CredentialReplicaScan(
            replicas: replicas.sorted { $0.deviceID < $1.deviceID },
            failures: failures.sorted { $0.deviceID < $1.deviceID }
        )
    }

    /// 校验信封后原子写入当前设备副本，并回读确认字节一致。
    public func write(_ envelope: CredentialEnvelope, deviceID: String) throws {
        guard UUID(uuidString: deviceID) != nil else {
            throw CredentialReplicaStoreError.invalidDeviceID(deviceID)
        }
        _ = try codec.open(envelope, for: .bailianAPIKey)

        try fileManager.createDirectory(
            at: replicasURL,
            withIntermediateDirectories: true
        )
        let url = replicaURL(deviceID: deviceID)
        if fileManager.fileExists(atPath: url.path) {
            try resolveIdenticalConflicts(at: url)
        }
        let data = try codec.encode(envelope)
        try data.write(to: url, options: [.atomic])
        guard try readData(at: url) == data else {
            throw CredentialReplicaStoreError.fileVerificationFailed
        }
    }

    /// removal marker 生效后删除指定设备的加密凭据副本；当前获胜值已由保留设备接管。
    public func removeReplica(deviceID: String) throws {
        guard UUID(uuidString: deviceID) != nil else {
            throw CredentialReplicaStoreError.invalidDeviceID(deviceID)
        }
        let url = replicaURL(deviceID: deviceID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// 读取并返回 `readData` 对应的同步核心领域数据。
    private func readData(at url: URL) throws -> Data {
        // File Provider 占位文件尚未完整下载时不得读取，否则会把暂时不可用误判为损坏。
        if fileManager.isUbiquitousItem(at: url) {
            let values = try url.resourceValues(
                forKeys: [.ubiquitousItemDownloadingStatusKey]
            )
            if values.ubiquitousItemDownloadingStatus != .current {
                throw CredentialReplicaStoreError.itemNotDownloaded(url)
            }
        }
        try resolveIdenticalConflicts(at: url)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    /// 仅自动解决内容完全相同的文件版本；不同内容保留为显式冲突。
    private func resolveIdenticalConflicts(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else {
            return
        }
        let currentData = try Data(contentsOf: url, options: [.mappedIfSafe])
        for conflict in conflicts {
            guard conflict.hasLocalContents,
                  (try? Data(contentsOf: conflict.url, options: [.mappedIfSafe])) == currentData
            else {
                throw CredentialReplicaStoreError.fileConflict(url)
            }
        }
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    /// 计算并返回 `replicaURL` 对应的同步核心领域数据或状态结果。
    private func replicaURL(deviceID: String) -> URL {
        replicasURL.appendingPathComponent("\(deviceID)\(Self.fileSuffix)")
    }

    private var replicasURL: URL {
        rootURL.appendingPathComponent(
            "credentials/replicas",
            isDirectory: true
        )
    }
}
