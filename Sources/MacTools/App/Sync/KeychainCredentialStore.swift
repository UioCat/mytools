// `KeychainCredentialStore` 的 iCloud Drive 同步系统集成实现。
// 负责文件协调、下载请求和后台调度，不定义同步合并规则。

import Foundation
import MacToolsCore
import Security

/// 描述 `LegacyKeychainCredentialReaderError` 在 iCloud Drive 同步系统集成中可取的状态、选项或错误。
enum LegacyKeychainCredentialReaderError: Error {
    case unexpectedStatus(OSStatus)
    case invalidValue
}

/// 管理 `LegacyKeychainCredentialReader` 在 iCloud Drive 同步系统集成中的生命周期、依赖和可变状态。
final class LegacyKeychainCredentialReader: LegacyCredentialReading, @unchecked Sendable {
    static let stableService = "com.mactools.credentials.v1"
    private let services: [String]

    /// 创建 `LegacyKeychainCredentialReader`，保存传入依赖并建立初始状态。
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

    /// 读取并返回 `read` 对应的 iCloud Drive 同步系统集成数据。
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

    /// 计算并返回 `baseQuery` 对应的 iCloud Drive 同步系统集成数据或状态结果。
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
