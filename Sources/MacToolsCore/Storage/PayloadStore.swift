import Foundation
import ImageIO

public struct PayloadObjectDescriptor: Equatable, Sendable {
    public let id: String
    public let contentHash: String
    public let relativePath: String
    public let format: String
    public let byteCount: Int
    public let wasCreated: Bool

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

public enum PayloadStoreError: Error, Equatable {
    case emptyPayload
    case invalidPNG
    case invalidRelativePath
    case missingObject
}

public final class PayloadStore: @unchecked Sendable {
    public static let formatVersion = 1

    public let rootDirectory: URL
    private let fileManager: FileManager
    private let accessLock = NSRecursiveLock()

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

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

    public func store(_ data: Data, format: String) throws -> PayloadObjectDescriptor {
        try withExclusiveAccess {
            try storeUnlocked(data, format: format)
        }
    }

    public func withExclusiveAccess<Value>(_ operation: () throws -> Value) rethrows -> Value {
        accessLock.lock()
        defer { accessLock.unlock() }
        return try operation()
    }

    public func contains(relativePath: String) -> Bool {
        withExclusiveAccess {
            guard let fileURL = fileURL(for: relativePath) else { return false }
            return fileManager.fileExists(atPath: fileURL.path)
        }
    }

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

    private func storeUnlocked(_ data: Data, format: String) throws -> PayloadObjectDescriptor {
        guard !data.isEmpty else {
            throw PayloadStoreError.emptyPayload
        }

        try prepareStorage()
        let normalizedFormat = Self.normalizedExtension(format)
        let contentHash = ClipboardContentHasher.sha256String(for: data)
        let relativePath = Self.relativeObjectPath(contentHash: contentHash, format: normalizedFormat)
        let destinationURL = rootDirectory.appendingPathComponent(relativePath)

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

    public func fileURL(for relativePath: String) -> URL? {
        guard Self.isValidRelativePath(relativePath) else {
            return nil
        }
        return rootDirectory.appendingPathComponent(relativePath)
    }

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

    public func discardIfCreated(_ descriptor: PayloadObjectDescriptor) {
        guard descriptor.wasCreated else {
            return
        }
        try? remove(relativePath: descriptor.relativePath)
    }

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

    private static func relativeObjectPath(contentHash: String, format: String) -> String {
        let prefix = String(contentHash.prefix(2))
        return "objects/sha256/\(prefix)/\(contentHash).\(format)"
    }

    private static func normalizedExtension(_ value: String) -> String {
        let withoutDot = value.hasPrefix(".") ? String(value.dropFirst()) : value
        let filtered = withoutDot.lowercased().filter { $0.isLetter || $0.isNumber }
        return filtered.isEmpty ? "bin" : filtered
    }

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

    static func isValidPNGData(_ data: Data) -> Bool {
        guard data.starts(with: pngSignature),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(imageSource) == .statusComplete,
              CGImageSourceGetCount(imageSource) > 0 else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil
    }

    private static func isValidRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("..") else {
            return false
        }
        return value.hasPrefix("objects/sha256/")
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
