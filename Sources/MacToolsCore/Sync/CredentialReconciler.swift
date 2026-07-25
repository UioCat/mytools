import Foundation

public enum CredentialReconcilerError: Error, Equatable, Sendable {
    case conflictingEqualClock
}

public struct CredentialReconciliationWinner: Equatable, Sendable {
    public var envelope: CredentialEnvelope
    public var record: CredentialEnvelopeRecord

    public init(
        envelope: CredentialEnvelope,
        record: CredentialEnvelopeRecord
    ) {
        self.envelope = envelope
        self.record = record
    }
}

public struct CredentialReconciler: Sendable {
    private let codec: CredentialEnvelopeCodec

    public init(codec: CredentialEnvelopeCodec = CredentialEnvelopeCodec()) {
        self.codec = codec
    }

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
            } else if candidate.record.clock == current.record.clock,
                      candidate.record != current.record {
                throw CredentialReconcilerError.conflictingEqualClock
            }
        }
        return winner
    }
}
