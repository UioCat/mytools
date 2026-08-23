// iCloud 文件协调适配器把 NSFileCoordinator/NSFileVersion 限制在 App 平台层。
// manifest 使用精确 URL 的普通协调写；正常内容更新不能误用 .forReplacing。

import Foundation
import MacToolsCore

final class ICloudSyncFileCoordinator: SyncFileCoordinating, @unchecked Sendable {
    func readData(at url: URL, options: Data.ReadingOptions) throws -> Data {
        let observation = try coordinateReading(at: url) { coordinatedURL in
            try ensureDownloaded(at: coordinatedURL)
            let data = try Data(contentsOf: coordinatedURL, options: options)
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinatedURL) ?? []
            for conflict in conflicts {
                guard conflict.hasLocalContents,
                      try readVersionData(conflict) == data else {
                    throw DriveSyncStoreError.fileConflict(coordinatedURL)
                }
            }
            return (data: data, hasIdenticalConflicts: !conflicts.isEmpty)
        }
        guard observation.hasIdenticalConflicts else { return observation.data }
        try coordinateWriting(at: url) { coordinatedURL in
            try resolveIdenticalConflictsInsideWrite(at: coordinatedURL)
        }
        return try coordinateReading(at: url) { coordinatedURL in
            try ensureDownloaded(at: coordinatedURL)
            return try Data(contentsOf: coordinatedURL, options: options)
        }
    }

    func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try coordinateWriting(at: url) { coordinatedURL in
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                try ensureDownloaded(at: coordinatedURL)
                try resolveIdenticalConflictsInsideWrite(at: coordinatedURL)
            }
            try data.write(to: coordinatedURL, options: [.atomic])
            guard try Data(contentsOf: coordinatedURL) == data else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    func coordinateManifest(
        at url: URL,
        deciding mutation: ([SyncFileVersionContent]) throws -> SyncManifestMutation
    ) throws -> SyncManifestMutationResult {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try coordinateWriting(at: url) { coordinatedURL in
            let currentData = FileManager.default.fileExists(atPath: coordinatedURL.path)
                ? try { try ensureDownloaded(at: coordinatedURL); return try Data(contentsOf: coordinatedURL) }()
                : nil
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinatedURL) ?? []
            var versionObjectsByID: [String: NSFileVersion] = [:]
            var versions: [SyncFileVersionContent] = []
            if let currentData {
                versions.append(
                    SyncFileVersionContent(
                        versionID: "current:\(SyncSnapshotCodec.digest(currentData))",
                        isCurrent: true,
                        data: currentData
                    )
                )
            }
            for (index, conflict) in conflicts.enumerated() {
                guard conflict.hasLocalContents else {
                    throw DriveSyncStoreError.itemNotDownloaded(conflict.url)
                }
                let data = try readVersionData(conflict)
                let versionID = "conflict:\(index):\(String(describing: conflict.persistentIdentifier)):\(SyncSnapshotCodec.digest(data))"
                versionObjectsByID[versionID] = conflict
                versions.append(
                    SyncFileVersionContent(
                        versionID: versionID,
                        isCurrent: false,
                        data: data
                    )
                )
            }

            switch try mutation(versions) {
            case let .keep(versionID):
                guard let kept = versions.first(where: { $0.versionID == versionID }) else {
                    throw DriveSyncStoreError.fileConflict(coordinatedURL)
                }
                if let historical = versionObjectsByID[versionID] {
                    _ = try historical.replaceItem(at: coordinatedURL, options: [])
                } else if !kept.isCurrent {
                    throw DriveSyncStoreError.fileConflict(coordinatedURL)
                }
                try resolve(conflicts: conflicts, at: coordinatedURL)
                let finalData = try Data(contentsOf: coordinatedURL)
                guard finalData == kept.data else {
                    throw DriveSyncStoreError.fileConflict(coordinatedURL)
                }
                return SyncManifestMutationResult(data: finalData, didWrite: false)

            case let .publish(data, baseVersionID):
                if let baseVersionID {
                    guard versions.contains(where: { $0.versionID == baseVersionID }) else {
                        throw DriveSyncStoreError.fileConflict(coordinatedURL)
                    }
                    if let historical = versionObjectsByID[baseVersionID] {
                        _ = try historical.replaceItem(at: coordinatedURL, options: [])
                    }
                } else if !versions.isEmpty {
                    throw DriveSyncStoreError.fileConflict(coordinatedURL)
                }
                try data.write(to: coordinatedURL, options: [.atomic])
                guard try Data(contentsOf: coordinatedURL) == data else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try resolve(conflicts: conflicts, at: coordinatedURL)
                return SyncManifestMutationResult(data: data, didWrite: true)

            case .abort:
                throw DriveSyncStoreError.fileConflict(coordinatedURL)
            }
        }
    }

    private func readVersionData(_ version: NSFileVersion) throws -> Data {
        try coordinateReading(at: version.url) { try Data(contentsOf: $0) }
    }

    /// 只能在同一 URL 的协调写 accessor 内调用。
    private func resolveIdenticalConflictsInsideWrite(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }
        let currentData = try Data(contentsOf: url, options: [.mappedIfSafe])
        for conflict in conflicts {
            guard conflict.hasLocalContents,
                  try readVersionData(conflict) == currentData else {
                throw DriveSyncStoreError.fileConflict(url)
            }
        }
        try resolve(conflicts: conflicts, at: url)
    }

    private func ensureDownloaded(at url: URL) throws {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard values.ubiquitousItemDownloadingStatus == .current else {
            throw DriveSyncStoreError.itemNotDownloaded(url)
        }
    }

    private func resolve(conflicts: [NSFileVersion], at url: URL) throws {
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    private func coordinateReading<T>(
        at url: URL,
        accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private func coordinateWriting<T>(
        at url: URL,
        accessor: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try accessor(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }
}
