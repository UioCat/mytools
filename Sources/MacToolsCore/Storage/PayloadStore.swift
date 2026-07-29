// `PayloadStore` 的本地存储领域实现。
// 负责数据库、载荷文件和迁移事务，不管理运行时面板状态。

import Foundation
import ImageIO

/// 封装 `PayloadObjectDescriptor` 在本地存储领域中的值语义和相关操作。
public struct PayloadObjectDescriptor: Equatable, Sendable {
    public let id: String
    public let contentHash: String
    public let relativePath: String
    public let format: String
    public let byteCount: Int
    public let wasCreated: Bool

    /// 创建 `PayloadObjectDescriptor`，保存传入依赖并建立初始状态。
    public init(
        id: String,
        contentHash: String,
        relativePath: String,
        format: String,
        byteCount: Int,
        wasCreated: Bool
    ) {
        self.id = id
        self.contentHash = contentHash
        self.relativePath = relativePath
        self.format = format
        self.byteCount = byteCount
        self.wasCreated = wasCreated
    }
}

/// 描述 `PayloadStoreError` 在本地存储领域中可取的状态、选项或错误。
public enum PayloadStoreError: Error, Equatable {
    case emptyPayload
    case invalidPNG
    case invalidRelativePath
    case missingObject
}

/// 以 SHA-256 内容寻址保存载荷文件，并通过递归锁串行化写入、删除和垃圾回收。
public final class PayloadStore: @unchecked Sendable {
    public static let formatVersion = 1

    public let rootDirectory: URL
    private let fileManager: FileManager
    private let accessLock = NSRecursiveLock()

    /// 创建 `PayloadStore`，保存传入依赖并建立初始状态。
    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// 校验 PNG 完整性后按内容哈希去重保存，并返回对象描述。
    public func storePNG(_ data: Data) throws -> PayloadObjectDescriptor {
        try withExclusiveAccess {
            guard !data.isEmpty else {
                throw PayloadStoreError.emptyPayload
            }
            guard Self.isValidPNGData(data) else {
                throw PayloadStoreError.invalidPNG
            }

            return try store(data, format: "png")
        }
    }

    /// 规范化并按 SHA-256 内容寻址写入载荷，使用 staging 和原子替换避免半文件。
    public func store(_ data: Data, format: String) throws -> PayloadObjectDescriptor {
        try withExclusiveAccess {
            try storeUnlocked(data, format: format)
        }
    }

    /// 在载荷存储的独占访问范围内执行传入操作，避免并发文件修改。
    public func withExclusiveAccess<Value>(_ operation: () throws -> Value) rethrows -> Value {
        accessLock.lock()
        defer { accessLock.unlock() }
        return try operation()
    }

    /// 验证相对路径安全后判断本地对象文件是否存在。
    public func contains(relativePath: String) -> Bool {
        withExclusiveAccess {
            guard let fileURL = fileURL(for: relativePath) else { return false }
            return fileManager.fileExists(atPath: fileURL.path)
        }
    }

    /// 枚举对象目录下所有合法存储对象的相对路径。
    public func objectRelativePaths() throws -> [String] {
        try withExclusiveAccess {
            guard fileManager.fileExists(atPath: objectsDirectory.path) else { return [] }
            let enumerator = fileManager.enumerator(
                at: objectsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            var paths: [String] = []
            while let fileURL = enumerator?.nextObject() as? URL {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let prefix = rootDirectory.standardizedFileURL.path + "/"
                let path = fileURL.standardizedFileURL.path
                guard path.hasPrefix(prefix) else { continue }
                paths.append(String(path.dropFirst(prefix.count)))
            }
            return paths
        }
    }

    /// 在已持有独占锁时写入内容寻址对象；相同哈希存在时校验并复用。
    private func storeUnlocked(_ data: Data, format: String) throws -> PayloadObjectDescriptor {
        guard !data.isEmpty else {
            throw PayloadStoreError.emptyPayload
        }

        try prepareStorage()
        let normalizedFormat = Self.normalizedExtension(format)
        let contentHash = ClipboardContentHasher.sha256String(for: data)
        let relativePath = Self.relativeObjectPath(contentHash: contentHash, format: normalizedFormat)
        let destinationURL = rootDirectory.appendingPathComponent(relativePath)

        // 同一哈希路径必须先回读校验；损坏对象会被当前已验证数据原子修复。
        if fileManager.fileExists(atPath: destinationURL.path) {
            let existing = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
            if Self.isValidStoredObject(existing, contentHash: contentHash, format: normalizedFormat) {
                return PayloadObjectDescriptor(
                    id: contentHash,
                    contentHash: contentHash,
                    relativePath: relativePath,
                    format: normalizedFormat,
                    byteCount: data.count,
                    wasCreated: false
                )
            }
            try data.write(to: destinationURL, options: [.atomic])
            try SensitiveFilePermissions.secureFile(at: destinationURL)
            return PayloadObjectDescriptor(
                id: contentHash,
                contentHash: contentHash,
                relativePath: relativePath,
                format: normalizedFormat,
                byteCount: data.count,
                wasCreated: false
            )
        }

        // 新对象先写入 staging 并收紧权限，再移动到最终哈希路径，避免暴露半写文件。
        let stagingURL = stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(normalizedFormat)
        try data.write(to: stagingURL, options: [.atomic])
        try SensitiveFilePermissions.secureFile(at: stagingURL)

        do {
            try SensitiveFilePermissions.prepareDirectory(at: destinationURL.deletingLastPathComponent())
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
                try SensitiveFilePermissions.secureFile(at: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }

        return PayloadObjectDescriptor(
            id: contentHash,
            contentHash: contentHash,
            relativePath: relativePath,
            format: normalizedFormat,
            byteCount: data.count,
            wasCreated: true
        )
    }

    /// 将经过路径穿越校验的相对对象路径解析为本地 URL。
    public func fileURL(for relativePath: String) -> URL? {
        guard Self.isValidRelativePath(relativePath) else {
            return nil
        }
        return rootDirectory.appendingPathComponent(relativePath)
    }

    /// 移除 `remove` 指定的本地存储领域数据，并维护关联状态。
    public func remove(relativePath: String) throws {
        try withExclusiveAccess {
            guard let fileURL = fileURL(for: relativePath) else {
                throw PayloadStoreError.invalidRelativePath
            }
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return
            }
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// 调整 `discardIfCreated` 涉及的本地存储领域状态，并保持迁移或恢复语义。
    public func discardIfCreated(_ descriptor: PayloadObjectDescriptor) {
        guard descriptor.wasCreated else {
            return
        }
        try? remove(relativePath: descriptor.relativePath)
    }

    /// 移除 `removeStagingFiles` 指定的本地存储领域数据，并维护关联状态。
    public func removeStagingFiles(olderThan cutoff: Date = .distantFuture) throws {
        try withExclusiveAccess {
            try prepareStorage()
            let entries = try fileManager.contentsOfDirectory(
                at: stagingDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            )
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) < cutoff else {
                    continue
                }
                try fileManager.removeItem(at: entry)
            }
        }
    }

    /// 汇总当前对象目录中所有普通文件的分配字节数。
    public func totalBytes() throws -> Int {
        guard fileManager.fileExists(atPath: objectsDirectory.path) else {
            return 0
        }
        let enumerator = fileManager.enumerator(
            at: objectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        var total = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += values.fileSize ?? 0
            }
        }
        return total
    }

    private var objectsDirectory: URL {
        rootDirectory
            .appendingPathComponent("objects", isDirectory: true)
            .appendingPathComponent("sha256", isDirectory: true)
    }

    private var stagingDirectory: URL {
        rootDirectory.appendingPathComponent("staging", isDirectory: true)
    }

    private var manifestURL: URL {
        rootDirectory.appendingPathComponent("store.json")
    }

    /// 创建对象和 staging 目录并收紧目录权限。
    private func prepareStorage() throws {
        try SensitiveFilePermissions.prepareDirectory(at: rootDirectory)
        try SensitiveFilePermissions.prepareDirectory(at: objectsDirectory)
        try SensitiveFilePermissions.prepareDirectory(at: stagingDirectory)
        if !fileManager.fileExists(atPath: manifestURL.path) {
            let manifest = Data("{\n  \"algorithm\" : \"sha256\",\n  \"version\" : 1\n}\n".utf8)
            try manifest.write(to: manifestURL, options: [.atomic])
        }
        try SensitiveFilePermissions.secureFile(at: manifestURL)
    }

    /// 使用摘要前缀分片生成稳定的内容寻址相对路径。
    private static func relativeObjectPath(contentHash: String, format: String) -> String {
        let prefix = String(contentHash.prefix(2))
        return "objects/sha256/\(prefix)/\(contentHash).\(format)"
    }

    /// 将格式名限制为可用于对象文件扩展名的安全字符。
    private static func normalizedExtension(_ value: String) -> String {
        let withoutDot = value.hasPrefix(".") ? String(value.dropFirst()) : value
        let filtered = withoutDot.lowercased().filter { $0.isLetter || $0.isNumber }
        return filtered.isEmpty ? "bin" : filtered
    }

    /// 校验已有对象的字节数、摘要和格式，防止复用损坏文件。
    private static func isValidStoredObject(
        _ data: Data,
        contentHash: String,
        format: String
    ) -> Bool {
        guard ClipboardContentHasher.sha256String(for: data) == contentHash else {
            return false
        }
        guard format == "png" else { return true }
        return isValidPNGData(data)
    }

    /// 使用 PNG 文件签名快速拒绝无效图片载荷。
    static func isValidPNGData(_ data: Data) -> Bool {
        guard data.starts(with: pngSignature),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(imageSource) == .statusComplete,
              CGImageSourceGetCount(imageSource) > 0 else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil
    }

    /// 拒绝绝对路径、空路径和父目录分量，确保对象访问不能逃逸根目录。
    private static func isValidRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("..") else {
            return false
        }
        return value.hasPrefix("objects/sha256/")
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
