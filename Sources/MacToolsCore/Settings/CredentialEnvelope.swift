// `CredentialEnvelope` 的设置与凭据领域实现。
// 负责配置、凭据信封和偏好持久化，不管理具体设置界面。

import CryptoKit
import Foundation

/// 描述 `CredentialEnvelopeState` 在设置与凭据领域中可取的状态、选项或错误。
public enum CredentialEnvelopeState: String, Codable, Equatable, Sendable {
    case active
    case deleted
}

/// 封装 `CredentialEnvelope` 在设置与凭据领域中的值语义和相关操作。
public struct CredentialEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var keyVersion: Int
    public var credentialID: String
    public var clock: ClipboardFieldClock
    public var sealedBox: Data

    /// 创建 `CredentialEnvelope`，保存传入依赖并建立初始状态。
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

/// 封装 `CredentialEnvelopeRecord` 在设置与凭据领域中的值语义和相关操作。
public struct CredentialEnvelopeRecord: Equatable, Sendable {
    public var credential: CredentialKey
    public var state: CredentialEnvelopeState
    public var value: String?
    public var clock: ClipboardFieldClock
    public var updatedAt: Date

    /// 创建 `CredentialEnvelopeRecord`，保存传入依赖并建立初始状态。
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

/// 描述 `CredentialEnvelopeCodecError` 在设置与凭据领域中可取的状态、选项或错误。
public enum CredentialEnvelopeCodecError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case unsupportedKeyVersion(Int)
    case unexpectedCredentialID(String)
    case invalidSealedBox
    case authenticationFailed
    case invalidPayload
}

/// 使用版本化头部和 AES-GCM 封装凭据，并校验状态、凭据类型与逻辑时钟。
public struct CredentialEnvelopeCodec: Sendable {
    public static let currentSchemaVersion = 1
    public static let currentKeyVersion = 1

    /// 封装 `AuthenticatedHeader` 在设置与凭据领域中的值语义和相关操作。
    private struct AuthenticatedHeader: Codable {
        var schemaVersion: Int
        var keyVersion: Int
        var credentialID: String
        var clock: ClipboardFieldClock
    }

    /// 封装 `SealedPayload` 在设置与凭据领域中的值语义和相关操作。
    private struct SealedPayload: Codable {
        var state: CredentialEnvelopeState
        var value: String?
        var updatedAt: Date
    }

    /// 创建 `CredentialEnvelopeCodec`，保存传入依赖并建立初始状态。
    public init() {}

    /// 规范化凭据值，以头部为 AAD 密封 active 或 deleted 载荷。
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
        // schema、key version、凭据 ID 和逻辑时钟均进入 AAD，任一字段被修改都会导致认证失败。
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

    /// 校验信封版本和凭据 ID，完成 AES-GCM 认证后返回规范化记录。
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

    /// 使用稳定键顺序和毫秒时间编码凭据信封，供本地及云端副本写入。
    public func encode(_ envelope: CredentialEnvelope) throws -> Data {
        try encoder().encode(envelope)
    }

    /// 解码信封结构；认证和凭据用途校验由 open 阶段完成。
    public func decode(_ data: Data) throws -> CredentialEnvelope {
        try decoder().decode(CredentialEnvelope.self, from: data)
    }

    /// 编码经过认证但不加密的协议头，作为 AES-GCM AAD。
    private func encodeHeader(_ header: AuthenticatedHeader) throws -> Data {
        try encoder().encode(header)
    }

    /// 编码实际凭据或删除标记，随后交给 AES-GCM 密封。
    private func encodePayload(_ payload: SealedPayload) throws -> Data {
        try encoder().encode(payload)
    }

    /// 创建稳定排序的编码器，确保 AAD 在不同设备上产生一致字节序列。
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    /// 创建与信封协议毫秒时间格式一致的解码器。
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    // 派生输入全部随源码公开，只提供稳定用途隔离和误读防护，不构成真正秘密。
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
