// `CredentialSyncEngine` 的同步核心领域实现。
// 负责协议模型、合并、对象存储和凭据对账，不管理 AppKit 生命周期。

import Foundation

/// 封装 `CredentialSyncResult` 在同步核心领域中的值语义和相关操作。
public struct CredentialSyncResult: Equatable, Sendable {
    public var winner: CredentialReconciliationWinner?
    public var failures: [CredentialReplicaFailure]

    /// 创建 `CredentialSyncResult`，保存传入依赖并建立初始状态。
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

/// 编排云端副本扫描、本地对账、迁移标记和当前设备副本回写。
public struct CredentialSyncEngine: Sendable {
    private let localStore: EncryptedCredentialStore

    /// 创建 `CredentialSyncEngine`，保存传入依赖并建立初始状态。
    public init(localStore: EncryptedCredentialStore) {
        self.localStore = localStore
    }

    /// 合并所有有效凭据副本，并把获胜信封写回本地与当前设备副本。
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
