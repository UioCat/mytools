// `CredentialReconciler` 的同步核心领域实现。
// 负责协议模型、合并、对象存储和凭据对账，不管理 AppKit 生命周期。

import Foundation

/// 描述 `CredentialReconcilerError` 在同步核心领域中可取的状态、选项或错误。
public enum CredentialReconcilerError: Error, Equatable, Sendable {
    case conflictingEqualClock
}

/// 封装 `CredentialReconciliationWinner` 在同步核心领域中的值语义和相关操作。
public struct CredentialReconciliationWinner: Equatable, Sendable {
    public var envelope: CredentialEnvelope
    public var record: CredentialEnvelopeRecord

    /// 创建 `CredentialReconciliationWinner`，保存传入依赖并建立初始状态。
    public init(
        envelope: CredentialEnvelope,
        record: CredentialEnvelopeRecord
    ) {
        self.envelope = envelope
        self.record = record
    }
}

/// 按逻辑时钟在本地信封和设备副本间选择唯一凭据获胜版本。
public struct CredentialReconciler: Sendable {
    private let codec: CredentialEnvelopeCodec

    /// 创建 `CredentialReconciler`，保存传入依赖并建立初始状态。
    public init(codec: CredentialEnvelopeCodec = CredentialEnvelopeCodec()) {
        self.codec = codec
    }

    /// 选择时钟最大的记录；相同时钟却内容不同视为协议冲突并拒绝猜测胜者。
    public func winner(
        local: CredentialEnvelope?,
        replicas: [CredentialReplica],
        for credential: CredentialKey
    ) throws -> CredentialReconciliationWinner? {
        var winner: CredentialReconciliationWinner?
        let envelopes = [local].compactMap { $0 } + replicas.map(\.envelope)
        for envelope in envelopes {
            let candidate = CredentialReconciliationWinner(
                envelope: envelope,
                record: try codec.open(envelope, for: credential)
            )
            guard let current = winner else {
                winner = candidate
                continue
            }
            if candidate.record.clock.wins(over: current.record.clock) {
                winner = candidate
            // 相同时钟必须表示同一记录，否则确定性排序也无法证明哪一份更新有效。
            } else if candidate.record.clock == current.record.clock,
                      candidate.record != current.record {
                throw CredentialReconcilerError.conflictingEqualClock
            }
        }
        return winner
    }
}
