// `SensitiveFilePermissions` 的基础设施工具实现。
// 提供日志和敏感文件权限等通用能力，不承载业务流程。

import Foundation

/// 描述 `SensitiveFilePermissions` 在基础设施工具中可取的状态、选项或错误。
enum SensitiveFilePermissions {
    /// 安排或刷新 `prepareDirectory` 对应的基础设施工具工作。
    static func prepareDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    /// 计算并返回 `secureFile` 对应的基础设施工具数据或状态结果。
    static func secureFile(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    /// 计算并返回 `secureRegularFiles` 对应的基础设施工具数据或状态结果。
    static func secureRegularFiles(in directory: URL) throws {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants]
        )

        for fileURL in fileURLs {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            try secureFile(at: fileURL)
        }
    }
}
