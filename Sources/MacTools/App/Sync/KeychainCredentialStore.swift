import Foundation
import MacToolsCore
import Security

enum KeychainCredentialStoreError: Error {
    case unexpectedStatus(OSStatus)
    case invalidValue
}

final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    static let stableService = "com.mactools.credentials.v1"
    private let service: String
    private let legacyServices: [String]
    private let synchronizes: Bool

    init(
        service: String = KeychainCredentialStore.stableService,
        legacyServices: [String] = [Bundle.main.bundleIdentifier, "local.mactools.mvp"].compactMap { $0 },
        synchronizes: Bool = true
    ) {
        self.service = service
        self.legacyServices = Array(Set(legacyServices)).filter { $0 != service }
        self.synchronizes = synchronizes
    }

    func read(_ key: CredentialKey) throws -> String? {
        if synchronizes {
            if let value = try read(key, service: service, synchronizable: true) {
                try? delete(key, service: service, synchronizable: false)
                return value
            }
            if let value = try read(key, service: service, synchronizable: false) {
                try save(value, for: key)
                try delete(key, service: service, synchronizable: false)
                return value
            }
        } else if let value = try read(key, service: service, synchronizable: false) {
            return value
        }
        for legacyService in legacyServices {
            let value: String?
            if synchronizes {
                value = try read(key, service: legacyService, synchronizable: true)
                    ?? read(key, service: legacyService, synchronizable: false)
            } else {
                value = try read(key, service: legacyService, synchronizable: false)
            }
            guard let value else { continue }
            try save(value, for: key)
            return value
        }
        return nil
    }

    private func read(
        _ key: CredentialKey,
        service: String,
        synchronizable: Bool
    ) throws -> String? {
        var query = baseQuery(for: key, service: service)
        query[kSecAttrSynchronizable as String] = synchronizable
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainCredentialStoreError.invalidValue
        }
        return value
    }

    func save(_ value: String, for key: CredentialKey) throws {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            try delete(key)
            return
        }

        var query = baseQuery(for: key)
        query[kSecAttrSynchronizable as String] = synchronizes
        let attributes: [String: Any] = [
            kSecValueData as String: Data(normalizedValue.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(updateStatus)
        }

        for (key, value) in attributes {
            query[key] = value
        }
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func delete(_ key: CredentialKey) throws {
        if synchronizes {
            try delete(key, service: service, synchronizable: true)
            try delete(key, service: service, synchronizable: false)
        } else {
            try delete(key, service: service, synchronizable: false)
        }
    }

    private func delete(
        _ key: CredentialKey,
        service: String,
        synchronizable: Bool
    ) throws {
        var query = baseQuery(for: key, service: service)
        query[kSecAttrSynchronizable as String] = synchronizable
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: CredentialKey, service: String? = nil) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service ?? self.service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}
