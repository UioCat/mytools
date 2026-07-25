import Foundation

public enum CredentialReplicaStoreError: Error, Equatable, Sendable {
    case invalidDeviceID(String)
    case itemNotDownloaded(URL)
    case fileConflict(URL)
    case unreadableReplica(String)
    case fileVerificationFailed
}

public struct CredentialReplica: Equatable, Sendable {
    public var deviceID: String
    public var envelope: CredentialEnvelope

    public init(deviceID: String, envelope: CredentialEnvelope) {
        self.deviceID = deviceID
        self.envelope = envelope
    }
}

public struct CredentialReplicaFailure: Equatable, Sendable {
    public var deviceID: String
    public var error: CredentialReplicaStoreError

    public init(deviceID: String, error: CredentialReplicaStoreError) {
        self.deviceID = deviceID
        self.error = error
    }
}

public struct CredentialReplicaScan: Equatable, Sendable {
    public var replicas: [CredentialReplica]
    public var failures: [CredentialReplicaFailure]

    public init(
        replicas: [CredentialReplica],
        failures: [CredentialReplicaFailure]
    ) {
        self.replicas = replicas
        self.failures = failures
    }
}

public final class CredentialReplicaStore: @unchecked Sendable {
    private static let fileSuffix = ".v1.json"

    public let rootURL: URL
    private let fileManager: FileManager
    private let codec: CredentialEnvelopeCodec

    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        codec: CredentialEnvelopeCodec = CredentialEnvelopeCodec()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.codec = codec
    }

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

    private func readData(at url: URL) throws -> Data {
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
