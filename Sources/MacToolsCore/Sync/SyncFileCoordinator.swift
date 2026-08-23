// 同步文件协调抽象将 Foundation 文件版本 API 隔离在平台目标中。
// Core 默认实现只服务普通本地文件系统和确定性单元测试。

import Foundation

/// 一个在同一协调访问区间内读取到的文件版本内容。
public struct SyncFileVersionContent: Equatable, Sendable {
    public var versionID: String
    public var isCurrent: Bool
    public var data: Data

    public init(versionID: String, isCurrent: Bool, data: Data) {
        self.versionID = versionID
        self.isCurrent = isCurrent
        self.data = data
    }
}

/// Core 在看到全部 manifest 文件版本后返回给平台适配器的原子操作。
public enum SyncManifestMutation: Equatable, Sendable {
    case keep(versionID: String)
    case publish(data: Data, baseVersionID: String?)
    case abort
}

/// 一次 manifest 协调操作的当前内容和是否实际写入结果。
public struct SyncManifestMutationResult: Equatable, Sendable {
    public var data: Data
    public var didWrite: Bool

    public init(data: Data, didWrite: Bool) {
        self.data = data
        self.didWrite = didWrite
    }
}

/// 为同步存储提供普通文件读写和 manifest 文件版本原子决策区间。
public protocol SyncFileCoordinating: Sendable {
    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func coordinateManifest(
        at url: URL,
        deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation
    ) throws -> SyncManifestMutationResult
}

public extension SyncFileCoordinating {
    func readData(at url: URL) throws -> Data {
        try readData(at: url, options: [])
    }
}

/// 不提供历史版本的直接文件实现；生产 iCloud 目录由 App 目标注入平台实现。
public struct DirectSyncFileCoordinator: SyncFileCoordinating {
    public init() {}

    public func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        try Data(contentsOf: url, options: options)
    }

    public func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
        guard try Data(contentsOf: url) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public func coordinateManifest(
        at url: URL,
        deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation
    ) throws -> SyncManifestMutationResult {
        let currentData = FileManager.default.fileExists(atPath: url.path)
            ? try Data(contentsOf: url)
            : nil
        let currentVersion = currentData.map {
            SyncFileVersionContent(
                versionID: "current:\(SyncSnapshotCodec.digest($0))",
                isCurrent: true,
                data: $0
            )
        }
        let versions = currentVersion.map { [$0] } ?? []
        switch try mutation(versions) {
        case let .keep(versionID):
            guard let currentVersion, currentVersion.versionID == versionID else {
                throw DriveSyncStoreError.fileConflict(url)
            }
            return SyncManifestMutationResult(data: currentVersion.data, didWrite: false)
        case let .publish(data, baseVersionID):
            guard baseVersionID == currentVersion?.versionID else {
                throw DriveSyncStoreError.fileConflict(url)
            }
            try writeData(data, to: url)
            return SyncManifestMutationResult(data: data, didWrite: true)
        case .abort:
            throw DriveSyncStoreError.fileConflict(url)
        }
    }
}
