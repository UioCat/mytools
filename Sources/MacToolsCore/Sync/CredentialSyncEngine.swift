import Foundation

public struct CredentialSyncResult: Equatable, Sendable {
    public var winner: CredentialReconciliationWinner?
    public var failures: [CredentialReplicaFailure]

    public init(
        winner: CredentialReconciliationWinner?,
        failures: [CredentialReplicaFailure]
    ) {
        self.winner = winner
        self.failures = failures
    }

    public var downloadURLs: [URL] {
        failures.compactMap {
            guard case let .itemNotDownloaded(url) = $0.error else { return nil }
            return url
        }
    }
}

public struct CredentialSyncEngine: Sendable {
    private let localStore: EncryptedCredentialStore

    public init(localStore: EncryptedCredentialStore) {
        self.localStore = localStore
    }

    public func synchronize(
        rootURL: URL,
        currentDeviceID: String,
        removedDeviceIDs: Set<String>
    ) throws -> CredentialSyncResult {
        let replicaStore = CredentialReplicaStore(rootURL: rootURL)
        let scan = try replicaStore.scan(excluding: removedDeviceIDs)
        let winner = try localStore.reconcile(
            replicas: scan.replicas,
            for: .bailianAPIKey
        )
        if let winner {
            if try !localStore.isMigrationComplete() {
                try localStore.markMigrationComplete()
            }
            try replicaStore.write(
                winner.envelope,
                deviceID: currentDeviceID
            )
        }
        return CredentialSyncResult(
            winner: winner,
            failures: scan.failures
        )
    }
}
