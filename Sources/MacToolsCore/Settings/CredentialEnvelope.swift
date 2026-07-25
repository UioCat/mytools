import CryptoKit
import Foundation

public enum CredentialEnvelopeState: String, Codable, Equatable, Sendable {
    case active
    case deleted
}

public struct CredentialEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var keyVersion: Int
    public var credentialID: String
    public var clock: ClipboardFieldClock
    public var sealedBox: Data

    public init(
        schemaVersion: Int,
        keyVersion: Int,
        credentialID: String,
        clock: ClipboardFieldClock,
        sealedBox: Data
    ) {
        self.schemaVersion = schemaVersion
        self.keyVersion = keyVersion
        self.credentialID = credentialID
        self.clock = clock
        self.sealedBox = sealedBox
    }
}

public struct CredentialEnvelopeRecord: Equatable, Sendable {
    public var credential: CredentialKey
    public var state: CredentialEnvelopeState
    public var value: String?
    public var clock: ClipboardFieldClock
    public var updatedAt: Date

    public init(
        credential: CredentialKey,
        state: CredentialEnvelopeState,
        value: String?,
        clock: ClipboardFieldClock,
        updatedAt: Date
    ) {
        self.credential = credential
        self.state = state
        self.value = value
        self.clock = clock
        self.updatedAt = updatedAt
    }
}

public enum CredentialEnvelopeCodecError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case unsupportedKeyVersion(Int)
    case unexpectedCredentialID(String)
    case invalidSealedBox
    case authenticationFailed
    case invalidPayload
}

public struct CredentialEnvelopeCodec: Sendable {
    public static let currentSchemaVersion = 1
    public static let currentKeyVersion = 1

    private struct AuthenticatedHeader: Codable {
        var schemaVersion: Int
        var keyVersion: Int
        var credentialID: String
        var clock: ClipboardFieldClock
    }

    private struct SealedPayload: Codable {
        var state: CredentialEnvelopeState
        var value: String?
        var updatedAt: Date
    }

    public init() {}

    public func seal(
        value: String?,
        for credential: CredentialKey,
        clock: ClipboardFieldClock,
        updatedAt: Date = Date()
    ) throws -> CredentialEnvelope {
        let normalizedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeValue = normalizedValue.flatMap { $0.isEmpty ? nil : $0 }
        let payload = SealedPayload(
            state: activeValue == nil ? .deleted : .active,
            value: activeValue,
            updatedAt: updatedAt
        )
        let header = AuthenticatedHeader(
            schemaVersion: Self.currentSchemaVersion,
            keyVersion: Self.currentKeyVersion,
            credentialID: credential.rawValue,
            clock: clock
        )
        let sealed = try AES.GCM.seal(
            encodePayload(payload),
            using: Self.derivedKey,
            authenticating: encodeHeader(header)
        )
        guard let combined = sealed.combined else {
            throw CredentialEnvelopeCodecError.invalidSealedBox
        }
        return CredentialEnvelope(
            schemaVersion: header.schemaVersion,
            keyVersion: header.keyVersion,
            credentialID: header.credentialID,
            clock: header.clock,
            sealedBox: combined
        )
    }

    public func open(
        _ envelope: CredentialEnvelope,
        for credential: CredentialKey
    ) throws -> CredentialEnvelopeRecord {
        guard envelope.schemaVersion == Self.currentSchemaVersion else {
            throw CredentialEnvelopeCodecError.unsupportedSchema(envelope.schemaVersion)
        }
        guard envelope.keyVersion == Self.currentKeyVersion else {
            throw CredentialEnvelopeCodecError.unsupportedKeyVersion(envelope.keyVersion)
        }
        guard envelope.credentialID == credential.rawValue else {
            throw CredentialEnvelopeCodecError.unexpectedCredentialID(envelope.credentialID)
        }

        let header = AuthenticatedHeader(
            schemaVersion: envelope.schemaVersion,
            keyVersion: envelope.keyVersion,
            credentialID: envelope.credentialID,
            clock: envelope.clock
        )
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: envelope.sealedBox)
        } catch {
            throw CredentialEnvelopeCodecError.invalidSealedBox
        }

        let payloadData: Data
        do {
            payloadData = try AES.GCM.open(
                sealedBox,
                using: Self.derivedKey,
                authenticating: encodeHeader(header)
            )
        } catch {
            throw CredentialEnvelopeCodecError.authenticationFailed
        }

        let payload: SealedPayload
        do {
            payload = try decoder().decode(SealedPayload.self, from: payloadData)
        } catch {
            throw CredentialEnvelopeCodecError.invalidPayload
        }
        switch payload.state {
        case .active:
            guard let value = payload.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                throw CredentialEnvelopeCodecError.invalidPayload
            }
            return CredentialEnvelopeRecord(
                credential: credential,
                state: .active,
                value: value,
                clock: envelope.clock,
                updatedAt: payload.updatedAt
            )
        case .deleted:
            guard payload.value == nil else {
                throw CredentialEnvelopeCodecError.invalidPayload
            }
            return CredentialEnvelopeRecord(
                credential: credential,
                state: .deleted,
                value: nil,
                clock: envelope.clock,
                updatedAt: payload.updatedAt
            )
        }
    }

    public func encode(_ envelope: CredentialEnvelope) throws -> Data {
        try encoder().encode(envelope)
    }

    public func decode(_ data: Data) throws -> CredentialEnvelope {
        try decoder().decode(CredentialEnvelope.self, from: data)
    }

    private func encodeHeader(_ header: AuthenticatedHeader) throws -> Data {
        try encoder().encode(header)
    }

    private func encodePayload(_ payload: SealedPayload) throws -> Data {
        try encoder().encode(payload)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static let derivedKey: SymmetricKey = {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(
                data: Data("MacTools/PublicCredentialMaterial/v1".utf8)
            ),
            salt: Data("MacTools/CredentialEnvelope/HKDF-SHA256".utf8),
            info: Data("bailian.apiKey/AES-256-GCM/key-v1".utf8),
            outputByteCount: 32
        )
    }()
}
