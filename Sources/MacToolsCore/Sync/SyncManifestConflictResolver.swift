// `SyncManifestConflictResolver` 只判断已验证 manifest 版本之间的单调关系。
// 文件版本枚举、快照读取和版本删除由平台与存储适配器负责。

import Foundation

/// 一个已经完成现场快照校验或由本机发布台账证明的 manifest 文件版本。
public struct SyncManifestCandidate: Equatable, Sendable {
    public enum Verification: Equatable, Sendable {
        /// manifest 引用的三个快照均已完成结构与摘要校验。
        case complete
        /// 本机台账证明该迟到祖先已被指定 revision 取代；它只能作为输家。
        case supersededLedger(replacedByRevision: Int64)
    }

    public var versionID: String
    public var isCurrent: Bool
    public var manifest: SyncReplicaManifest
    public var manifestDigest: String
    public var verification: Verification

    public init(
        versionID: String,
        isCurrent: Bool,
        manifest: SyncReplicaManifest,
        manifestDigest: String,
        verification: Verification
    ) {
        self.versionID = versionID
        self.isCurrent = isCurrent
        self.manifest = manifest
        self.manifestDigest = manifestDigest
        self.verification = verification
    }
}

/// manifest 冲突的确定性决策；证据不足时必须保留所有文件版本。
public enum SyncManifestConflictResolution: Equatable, Sendable {
    case keep(versionID: String)
    case unresolved
}

/// 选择唯一、完整且逐项支配其他候选的 manifest 版本。
public enum SyncManifestConflictResolver {
    public static func resolve(
        _ candidates: [SyncManifestCandidate]
    ) -> SyncManifestConflictResolution {
        guard !candidates.isEmpty,
              Set(candidates.map(\.versionID)).count == candidates.count,
              candidates.allSatisfy(isStructurallyValid),
              allCandidatesShareReplicaIdentity(candidates) else {
            return .unresolved
        }

        let winners = candidates.filter { candidate in
            guard candidate.verification == .complete else { return false }
            return candidates.allSatisfy { other in
                candidate.versionID == other.versionID || dominates(candidate, other)
            }
        }
        guard winners.count == 1, let winner = winners.first else {
            return .unresolved
        }
        return .keep(versionID: winner.versionID)
    }

    private static func isStructurallyValid(_ candidate: SyncManifestCandidate) -> Bool {
        let manifest = candidate.manifest
        guard manifest.schemaVersion == SyncReplicaManifest.currentSchemaVersion,
              manifest.revision >= 0,
              manifest.seenRevisions.values.allSatisfy({ $0 >= 0 }),
              manifest.seenRevisions[manifest.deviceID] == manifest.revision else {
            return false
        }
        if case let .supersededLedger(replacedByRevision) = candidate.verification {
            return replacedByRevision > manifest.revision
        }
        return true
    }

    private static func allCandidatesShareReplicaIdentity(
        _ candidates: [SyncManifestCandidate]
    ) -> Bool {
        guard let first = candidates.first?.manifest else { return false }
        return candidates.allSatisfy {
            $0.manifest.schemaVersion == first.schemaVersion
                && $0.manifest.deviceID == first.deviceID
                && $0.manifest.generation == first.generation
        }
    }

    private static func dominates(
        _ winner: SyncManifestCandidate,
        _ other: SyncManifestCandidate
    ) -> Bool {
        guard winner.manifest.revision >= other.manifest.revision else { return false }
        if case let .supersededLedger(replacedByRevision) = other.verification,
           winner.manifest.revision < replacedByRevision {
            return false
        }
        let deviceIDs = Set(winner.manifest.seenRevisions.keys)
            .union(other.manifest.seenRevisions.keys)
        return deviceIDs.allSatisfy {
            (winner.manifest.seenRevisions[$0] ?? 0)
                >= (other.manifest.seenRevisions[$0] ?? 0)
        }
    }
}
