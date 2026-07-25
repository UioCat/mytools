import Foundation
import MacToolsCore
import Security

enum LegacyKeychainCredentialReaderError: Error {
    case unexpectedStatus(OSStatus)
    case invalidValue
}

final class LegacyKeychainCredentialReader: LegacyCredentialReading, @unchecked Sendable {
    static let stableService = "com.mactools.credentials.v1"
    private let services: [String]

    init(
        service: String = LegacyKeychainCredentialReader.stableService,
        legacyServices: [String] = [
            Bundle.main.bundleIdentifier,
            "local.mactools.mvp"
        ].compactMap { $0 }
    ) {
        var seen: Set<String> = []
        self.services = ([service] + legacyServices).filter {
            seen.insert($0).inserted
        }
    }

    func read(_ key: CredentialKey) throws -> String? {
        for service in services {
            var query = baseQuery(for: key, service: service)
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                continue
            }
            guard status == errSecSuccess else {
                throw LegacyKeychainCredentialReaderError.unexpectedStatus(status)
            }
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw LegacyKeychainCredentialReaderError.invalidValue
            }
            return value
        }
        return nil
    }

    private func baseQuery(
        for key: CredentialKey,
        service: String
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
