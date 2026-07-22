import Foundation

public enum DriveSyncStoreError: Error, Equatable, Sendable {
    case missingProtocol
    case incompatibleProtocol(found: Int)
    case incompatibleSchema(fileName: String, found: Int)
    case itemNotDownloaded(URL)
    case invalidContentID(String)
    case snapshotDigestMismatch(deviceID: String, fileName: String)
    case inconsistentReplica(deviceID: String)
    case unreadableReplica(deviceID: String)
    case unreadableContent(String)
    case fileConflict(URL)
    case contentHashMismatch(String)
}

public struct DriveSyncReplica: Equatable, Sendable {
    public var manifest: SyncReplicaManifest
    public var clipboard: SyncClipboardSnapshot
    public var preferences: SyncPreferencesSnapshot
    public var tombstones: SyncTombstoneSnapshot
    public var manifestDigest: String

    public init(
        manifest: SyncReplicaManifest,
        clipboard: SyncClipboardSnapshot,
        preferences: SyncPreferencesSnapshot,
        tombstones: SyncTombstoneSnapshot,
        manifestDigest: String
    ) {
        self.manifest = manifest
        self.clipboard = clipboard
        self.preferences = preferences
        self.tombstones = tombstones
        self.manifestDigest = manifestDigest
    }
}

public struct SyncStoredObject: Equatable, Sendable {
    public var contentID: String
    public var kind: ClipboardContentKind
    public var byteCount: Int64

    public init(contentID: String, kind: ClipboardContentKind, byteCount: Int64) {
        self.contentID = contentID
        self.kind = kind
        self.byteCount = byteCount
    }
}

public struct DriveSyncReplicaFailure: Equatable, Sendable {
    public var deviceID: String
    public var error: DriveSyncStoreError

    public init(deviceID: String, error: DriveSyncStoreError) {
        self.deviceID = deviceID
        self.error = error
    }
}

public struct DriveSyncReplicaScan: Equatable, Sendable {
    public var replicas: [DriveSyncReplica]
    public var failures: [DriveSyncReplicaFailure]

    public init(replicas: [DriveSyncReplica], failures: [DriveSyncReplicaFailure]) {
        self.replicas = replicas
        self.failures = failures
    }
}

public final class DriveSyncStore: @unchecked Sendable {
    public static let rootDirectoryName = "MacTools Sync"

    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    @discardableResult
    public func prepare(
        initialCapacity: SyncStorageLimit = .default,
        now: Date = Date()
    ) throws -> SyncProtocolDescriptor {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for directory in [objectsTextURL, objectsImagesURL, replicasURL, evictionsURL, resetsURL, removedDevicesURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: keepURL.path) {
            try Data().write(to: keepURL, options: [.atomic])
        }
        if fileManager.fileExists(atPath: protocolURL.path) {
            return try readProtocol()
        }
        let descriptor = SyncProtocolDescriptor(
            storeID: UUID(),
            createdAt: now,
            capacityLimit: initialCapacity
        )
        try verifiedWrite(SyncSnapshotCodec.encode(descriptor), to: protocolURL)
        return descriptor
    }

    public func readProtocol() throws -> SyncProtocolDescriptor {
        guard fileManager.fileExists(atPath: protocolURL.path) else {
            throw DriveSyncStoreError.missingProtocol
        }
        let descriptor = try SyncSnapshotCodec.decode(
            SyncProtocolDescriptor.self,
            from: readData(at: protocolURL)
        )
        guard descriptor.protocolVersion == SyncProtocolDescriptor.currentVersion else {
            throw DriveSyncStoreError.incompatibleProtocol(found: descriptor.protocolVersion)
        }
        return descriptor
    }

    public func replicas(generation: Int) throws -> [DriveSyncReplica] {
        try scanReplicas(generation: generation).replicas
    }

    public func scanReplicas(generation: Int) throws -> DriveSyncReplicaScan {
        guard fileManager.fileExists(atPath: replicasURL.path) else {
            return DriveSyncReplicaScan(replicas: [], failures: [])
        }
        let directories = try fileManager.contentsOfDirectory(
            at: replicasURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var replicas: [DriveSyncReplica] = []
        var failures: [DriveSyncReplicaFailure] = []
        for directory in directories {
            let deviceID = directory.lastPathComponent
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }
                if let replica = try readReplica(at: directory, generation: generation) {
                    replicas.append(replica)
                }
            } catch let error as DriveSyncStoreError {
                failures.append(DriveSyncReplicaFailure(deviceID: deviceID, error: error))
            } catch {
                failures.append(
                    DriveSyncReplicaFailure(
                        deviceID: deviceID,
                        error: .unreadableReplica(deviceID: deviceID)
                    )
                )
            }
        }
        return DriveSyncReplicaScan(
            replicas: replicas.sorted { $0.manifest.deviceID < $1.manifest.deviceID },
            failures: failures.sorted { $0.deviceID < $1.deviceID }
        )
    }

    public func write(
        _ bundle: SyncExportBundle,
        seenRevisions: [String: Int64],
        deviceName: String? = nil,
        updatedAt: Date
    ) throws -> SyncReplicaManifest {
        for content in bundle.contents {
            try writeContentIfNeeded(content)
        }

        let deviceDirectory = replicasURL.appendingPathComponent(
            bundle.clipboard.deviceID,
            isDirectory: true
        )
        try fileManager.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)

        let clipboardData = try SyncSnapshotCodec.encode(bundle.clipboard)
        let preferencesData = try SyncSnapshotCodec.encode(bundle.preferences)
        let tombstonesData = try SyncSnapshotCodec.encode(bundle.tombstones)
        let snapshotDigests = SyncSnapshotDigests(
            clipboard: SyncSnapshotCodec.digest(clipboardData),
            preferences: SyncSnapshotCodec.digest(preferencesData),
            tombstones: SyncSnapshotCodec.digest(tombstonesData)
        )
        let snapshotDirectoryName = Self.snapshotDirectoryName(
            generation: bundle.clipboard.generation,
            revision: bundle.clipboard.revision
        )
        let revisionsDirectory = deviceDirectory.appendingPathComponent("revisions", isDirectory: true)
        let snapshotDirectory = revisionsDirectory.appendingPathComponent(
            snapshotDirectoryName,
            isDirectory: true
        )
        try writeSnapshotRevision(
            clipboardData: clipboardData,
            preferencesData: preferencesData,
            tombstonesData: tombstonesData,
            to: snapshotDirectory,
            revisionsDirectory: revisionsDirectory
        )

        let manifest = SyncReplicaManifest(
            deviceID: bundle.clipboard.deviceID,
            deviceName: deviceName,
            generation: bundle.clipboard.generation,
            revision: bundle.clipboard.revision,
            seenRevisions: seenRevisions,
            snapshotDigests: snapshotDigests,
            snapshotDirectory: snapshotDirectoryName,
            updatedAt: updatedAt
        )
        let previousManifest = currentManifest(at: deviceDirectory)
        let manifestData = try SyncSnapshotCodec.encode(manifest)
        try verifiedWrite(
            manifestData,
            to: deviceDirectory.appendingPathComponent("manifest.json")
        )
        try removeObsoleteSnapshotRevisions(
            in: revisionsDirectory,
            keeping: Set([snapshotDirectoryName, previousManifest?.snapshotDirectory].compactMap { $0 })
        )
        return try SyncSnapshotCodec.decode(SyncReplicaManifest.self, from: manifestData)
    }

    public func contentData(contentID: String, kind: ClipboardContentKind) throws -> Data? {
        let url = try contentURL(contentID: contentID, kind: kind)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try readData(at: url, options: [.mappedIfSafe])
        } catch let error as DriveSyncStoreError {
            throw error
        } catch {
            throw DriveSyncStoreError.unreadableContent(contentID)
        }
        try validateContent(data, contentID: contentID, kind: kind)
        return data
    }

    public func contentFileURL(contentID: String, kind: ClipboardContentKind) throws -> URL {
        try contentURL(contentID: contentID, kind: kind)
    }

    public func writeEvictions(_ snapshot: SyncEvictionSnapshot) throws {
        try verifiedWrite(
            SyncSnapshotCodec.encode(snapshot),
            to: evictionsURL.appendingPathComponent("\(snapshot.deviceID).json")
        )
    }

    public func evictions(generation: Int) throws -> [SyncEvictionRecord] {
        try jsonFiles(in: evictionsURL).flatMap { url -> [SyncEvictionRecord] in
            let snapshot = try SyncSnapshotCodec.decode(
                SyncEvictionSnapshot.self,
                from: readData(at: url)
            )
            try validateSchema(
                snapshot.schemaVersion,
                expected: SyncEvictionSnapshot.currentSchemaVersion,
                fileName: url.lastPathComponent
            )
            guard snapshot.generation == generation else { return [] }
            return snapshot.records
        }
    }

    public func evictionSnapshot(deviceID: String) throws -> SyncEvictionSnapshot? {
        let url = evictionsURL.appendingPathComponent("\(deviceID).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let snapshot = try SyncSnapshotCodec.decode(
            SyncEvictionSnapshot.self,
            from: readData(at: url)
        )
        try validateSchema(
            snapshot.schemaVersion,
            expected: SyncEvictionSnapshot.currentSchemaVersion,
            fileName: url.lastPathComponent
        )
        return snapshot
    }

    public func writeReset(_ marker: SyncResetMarker) throws {
        try verifiedWrite(
            SyncSnapshotCodec.encode(marker),
            to: resetsURL.appendingPathComponent("\(marker.deviceID).json")
        )
    }

    public func highestResetGeneration() throws -> Int {
        try jsonFiles(in: resetsURL).reduce(1) { value, url in
            let marker = try SyncSnapshotCodec.decode(
                SyncResetMarker.self,
                from: readData(at: url)
            )
            try validateSchema(
                marker.schemaVersion,
                expected: SyncResetMarker.currentSchemaVersion,
                fileName: url.lastPathComponent
            )
            return max(value, marker.generation)
        }
    }

    public func writeRemovedDevice(_ marker: SyncRemovedDeviceMarker) throws {
        let directory = removedDevicesURL.appendingPathComponent(
            marker.removedDeviceID,
            isDirectory: true
        )
        try verifiedWrite(
            SyncSnapshotCodec.encode(marker),
            to: directory.appendingPathComponent("\(marker.removerDeviceID).json")
        )
    }

    public func removedDeviceIDs(generation: Int) throws -> Set<String> {
        guard fileManager.fileExists(atPath: removedDevicesURL.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: removedDevicesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var removed: Set<String> = []
        for directory in directories {
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            for url in try jsonFiles(in: directory) {
                let marker = try SyncSnapshotCodec.decode(
                    SyncRemovedDeviceMarker.self,
                    from: readData(at: url)
                )
                try validateSchema(
                    marker.schemaVersion,
                    expected: SyncRemovedDeviceMarker.currentSchemaVersion,
                    fileName: url.lastPathComponent
                )
                guard marker.generation <= generation,
                      marker.removedDeviceID == directory.lastPathComponent else {
                    continue
                }
                removed.insert(marker.removedDeviceID)
            }
        }
        return removed
    }

    public func usage(capacityBytes: Int64, ordinaryHistoryCount: Int) throws -> SyncStorageUsage {
        var imageBytes: Int64 = 0
        var textBytes: Int64 = 0
        var metadataBytes: Int64 = 0
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return SyncStorageUsage(
                usedBytes: 0,
                capacityBytes: capacityBytes,
                ordinaryHistoryCount: ordinaryHistoryCount,
                imageBytes: 0,
                textBytes: 0,
                metadataBytes: 0
            )
        }
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let bytes = Int64(values.fileSize ?? 0)
            let directoryKind = storedObjectDirectoryKind(for: url)
            if directoryKind == .imageData {
                imageBytes += bytes
            } else if directoryKind == .text {
                textBytes += bytes
            } else {
                metadataBytes += bytes
            }
        }
        return SyncStorageUsage(
            usedBytes: imageBytes + textBytes + metadataBytes,
            capacityBytes: capacityBytes,
            ordinaryHistoryCount: ordinaryHistoryCount,
            imageBytes: imageBytes,
            textBytes: textBytes,
            metadataBytes: metadataBytes
        )
    }

    private func storedObjectDirectoryKind(for url: URL) -> ClipboardContentKind? {
        let components = url.pathComponents
        guard let objectsIndex = components.lastIndex(of: "objects"),
              components.indices.contains(objectsIndex + 2),
              components[objectsIndex + 2] == "sha256" else {
            return nil
        }
        switch components[objectsIndex + 1] {
        case "text": return .text
        case "images": return .imageData
        default: return nil
        }
    }

    public func removeReplicaData() throws {
        for url in [replicasURL, evictionsURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func storedObjects() throws -> [SyncStoredObject] {
        var objects: [SyncStoredObject] = []
        try appendStoredObjects(in: objectsTextURL, kind: .text, extension: "json", to: &objects)
        try appendStoredObjects(in: objectsImagesURL, kind: .imageData, extension: "png", to: &objects)
        return objects.sorted { $0.contentID < $1.contentID }
    }

    public func removeObject(_ object: SyncStoredObject) throws {
        let url = try contentURL(contentID: object.contentID, kind: object.kind)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let data = try readData(at: url, options: [.mappedIfSafe])
        if object.kind == .text {
            let decoded = try SyncSnapshotCodec.decode(SyncTextContentObject.self, from: data)
            try validateContent(data, contentID: object.contentID, kind: decoded.kind)
        } else {
            try validateContent(data, contentID: object.contentID, kind: object.kind)
        }
        try fileManager.removeItem(at: url)
    }

    private func readReplica(at directory: URL, generation: Int) throws -> DriveSyncReplica? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let manifestData = try readData(at: manifestURL)
        let manifest = try SyncSnapshotCodec.decode(SyncReplicaManifest.self, from: manifestData)
        guard [1, SyncReplicaManifest.currentSchemaVersion].contains(manifest.schemaVersion) else {
            throw DriveSyncStoreError.incompatibleSchema(
                fileName: manifestURL.lastPathComponent,
                found: manifest.schemaVersion
            )
        }
        guard manifest.generation == generation else { return nil }
        guard manifest.deviceID == directory.lastPathComponent else {
            throw DriveSyncStoreError.inconsistentReplica(deviceID: directory.lastPathComponent)
        }

        let snapshotDirectory: URL
        if let snapshotDirectoryName = manifest.snapshotDirectory {
            guard Self.isValidSnapshotDirectoryName(snapshotDirectoryName) else {
                throw DriveSyncStoreError.inconsistentReplica(deviceID: manifest.deviceID)
            }
            snapshotDirectory = directory
                .appendingPathComponent("revisions", isDirectory: true)
                .appendingPathComponent(snapshotDirectoryName, isDirectory: true)
        } else {
            snapshotDirectory = directory
        }
        let clipboardData = try snapshotData(
            named: "clipboard.json",
            expectedDigest: manifest.snapshotDigests.clipboard,
            deviceID: manifest.deviceID,
            directory: snapshotDirectory
        )
        let preferencesData = try snapshotData(
            named: "preferences.json",
            expectedDigest: manifest.snapshotDigests.preferences,
            deviceID: manifest.deviceID,
            directory: snapshotDirectory
        )
        let tombstonesData = try snapshotData(
            named: "tombstones.json",
            expectedDigest: manifest.snapshotDigests.tombstones,
            deviceID: manifest.deviceID,
            directory: snapshotDirectory
        )
        let clipboard = try SyncSnapshotCodec.decode(SyncClipboardSnapshot.self, from: clipboardData)
        let preferences = try SyncSnapshotCodec.decode(SyncPreferencesSnapshot.self, from: preferencesData)
        let tombstones = try SyncSnapshotCodec.decode(SyncTombstoneSnapshot.self, from: tombstonesData)
        try validateSchema(
            clipboard.schemaVersion,
            expected: SyncClipboardSnapshot.currentSchemaVersion,
            fileName: "clipboard.json"
        )
        try validateSchema(
            preferences.schemaVersion,
            expected: SyncPreferencesSnapshot.currentSchemaVersion,
            fileName: "preferences.json"
        )
        try validateSchema(
            tombstones.schemaVersion,
            expected: SyncTombstoneSnapshot.currentSchemaVersion,
            fileName: "tombstones.json"
        )
        guard clipboard.deviceID == manifest.deviceID,
              preferences.deviceID == manifest.deviceID,
              tombstones.deviceID == manifest.deviceID,
              clipboard.revision == manifest.revision,
              preferences.revision == manifest.revision,
              tombstones.revision == manifest.revision,
              clipboard.generation == generation,
              preferences.generation == generation,
              tombstones.generation == generation else {
            throw DriveSyncStoreError.inconsistentReplica(deviceID: manifest.deviceID)
        }
        return DriveSyncReplica(
            manifest: manifest,
            clipboard: clipboard,
            preferences: preferences,
            tombstones: tombstones,
            manifestDigest: SyncSnapshotCodec.digest(manifestData)
        )
    }

    private func snapshotData(
        named fileName: String,
        expectedDigest: String,
        deviceID: String,
        directory: URL
    ) throws -> Data {
        let data = try readData(at: directory.appendingPathComponent(fileName))
        guard SyncSnapshotCodec.digest(data) == expectedDigest else {
            throw DriveSyncStoreError.snapshotDigestMismatch(
                deviceID: deviceID,
                fileName: fileName
            )
        }
        return data
    }

    private func writeSnapshotRevision(
        clipboardData: Data,
        preferencesData: Data,
        tombstonesData: Data,
        to destination: URL,
        revisionsDirectory: URL
    ) throws {
        try fileManager.createDirectory(at: revisionsDirectory, withIntermediateDirectories: true)
        let staging = revisionsDirectory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try verifiedWrite(clipboardData, to: staging.appendingPathComponent("clipboard.json"))
            try verifiedWrite(preferencesData, to: staging.appendingPathComponent("preferences.json"))
            try verifiedWrite(tombstonesData, to: staging.appendingPathComponent("tombstones.json"))
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func currentManifest(at deviceDirectory: URL) -> SyncReplicaManifest? {
        let url = deviceDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? readData(at: url) else {
            return nil
        }
        return try? SyncSnapshotCodec.decode(SyncReplicaManifest.self, from: data)
    }

    private func removeObsoleteSnapshotRevisions(
        in revisionsDirectory: URL,
        keeping names: Set<String>
    ) throws {
        guard fileManager.fileExists(atPath: revisionsDirectory.path) else { return }
        for url in try fileManager.contentsOfDirectory(
            at: revisionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) where !names.contains(url.lastPathComponent) {
            try fileManager.removeItem(at: url)
        }
    }

    private func writeContentIfNeeded(_ content: SyncExportContent) throws {
        let url = try contentURL(contentID: content.contentID, kind: content.kind)
        try validateContent(content.data, contentID: content.contentID, kind: content.kind)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try validateContent(
                    readData(at: url, options: [.mappedIfSafe]),
                    contentID: content.contentID,
                    kind: content.kind
                )
                return
            } catch let error as DriveSyncStoreError {
                switch error {
                case .itemNotDownloaded, .fileConflict:
                    throw error
                default:
                    break
                }
            } catch {
                // A complete local content object can safely repair corrupt bytes
                // at the same content-addressed path when no iCloud conflict exists.
            }
            try verifiedWrite(content.data, to: url)
            return
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try verifiedWrite(content.data, to: url)
    }

    private func validateContent(_ data: Data, contentID: String, kind: ClipboardContentKind) throws {
        let actualHash: String
        switch kind {
        case .text, .url:
            let object: SyncTextContentObject
            do {
                object = try SyncSnapshotCodec.decode(SyncTextContentObject.self, from: data)
            } catch {
                throw DriveSyncStoreError.contentHashMismatch(contentID)
            }
            try validateSchema(
                object.schemaVersion,
                expected: SyncTextContentObject.currentSchemaVersion,
                fileName: "\(contentID).json"
            )
            guard object.contentID == contentID, object.kind == kind else {
                throw DriveSyncStoreError.contentHashMismatch(contentID)
            }
            actualHash = ClipboardContentHasher.sha256String(
                for: Data("text:\(object.text)".utf8)
            )
        case .imageData:
            guard PayloadStore.isValidPNGData(data) else {
                throw DriveSyncStoreError.contentHashMismatch(contentID)
            }
            actualHash = ClipboardContentHasher.sha256String(for: data)
        default:
            throw DriveSyncStoreError.contentHashMismatch(contentID)
        }
        guard actualHash == contentID else {
            throw DriveSyncStoreError.contentHashMismatch(contentID)
        }
    }

    private func contentURL(contentID: String, kind: ClipboardContentKind) throws -> URL {
        guard Self.isValidContentID(contentID) else {
            throw DriveSyncStoreError.invalidContentID(contentID)
        }
        let prefix = String(contentID.prefix(2))
        switch kind {
        case .text, .url:
            return objectsTextURL
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(contentID)
                .appendingPathExtension("json")
        case .imageData:
            return objectsImagesURL
                .appendingPathComponent(prefix, isDirectory: true)
                .appendingPathComponent(contentID)
                .appendingPathExtension("png")
        default:
            throw DriveSyncStoreError.invalidContentID(contentID)
        }
    }

    private func verifiedWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: url.path) {
            try resolveIdenticalConflicts(at: url)
        }
        try data.write(to: url, options: [.atomic])
        guard try readData(at: url) == data else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func readData(
        at url: URL,
        options: Data.ReadingOptions = []
    ) throws -> Data {
        if fileManager.isUbiquitousItem(at: url) {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus != .current {
                throw DriveSyncStoreError.itemNotDownloaded(url)
            }
        }
        try resolveIdenticalConflicts(at: url)
        return try Data(contentsOf: url, options: options)
    }

    private func resolveIdenticalConflicts(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else {
            return
        }
        let currentData = try Data(contentsOf: url, options: [.mappedIfSafe])
        for conflict in conflicts {
            guard conflict.hasLocalContents,
                  (try? Data(contentsOf: conflict.url, options: [.mappedIfSafe])) == currentData else {
                throw DriveSyncStoreError.fileConflict(url)
            }
        }
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    private func validateSchema(_ found: Int, expected: Int, fileName: String) throws {
        guard found == expected else {
            throw DriveSyncStoreError.incompatibleSchema(fileName: fileName, found: found)
        }
    }

    private func jsonFiles(in directory: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func appendStoredObjects(
        in directory: URL,
        kind: ClipboardContentKind,
        extension fileExtension: String,
        to result: inout [SyncStoredObject]
    ) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, url.pathExtension == fileExtension else { continue }
            let contentID = url.deletingPathExtension().lastPathComponent
            guard Self.isValidContentID(contentID) else { continue }
            result.append(
                SyncStoredObject(
                    contentID: contentID,
                    kind: kind,
                    byteCount: Int64(values.fileSize ?? 0)
                )
            )
        }
    }

    private static func isValidContentID(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func snapshotDirectoryName(generation: Int, revision: Int64) -> String {
        "g\(generation)-r\(revision)-\(UUID().uuidString.lowercased())"
    }

    private static func isValidSnapshotDirectoryName(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 160
            && !value.hasPrefix(".")
            && !value.contains("/")
            && !value.contains("..")
    }

    private var protocolURL: URL { rootURL.appendingPathComponent("protocol.json") }
    private var keepURL: URL { rootURL.appendingPathComponent(".mactools-keep") }
    private var replicasURL: URL { rootURL.appendingPathComponent("replicas", isDirectory: true) }
    private var evictionsURL: URL { rootURL.appendingPathComponent("evictions", isDirectory: true) }
    private var resetsURL: URL { rootURL.appendingPathComponent("resets", isDirectory: true) }
    private var removedDevicesURL: URL { rootURL.appendingPathComponent("removed-devices", isDirectory: true) }
    private var objectsTextURL: URL {
        rootURL.appendingPathComponent("objects/text/sha256", isDirectory: true)
    }
    private var objectsImagesURL: URL {
        rootURL.appendingPathComponent("objects/images/sha256", isDirectory: true)
    }
}
