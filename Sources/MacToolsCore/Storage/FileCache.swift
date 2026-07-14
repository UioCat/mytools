import Foundation

public struct CachedFile: Equatable {
    public let fileURL: URL
}

public final class FileCache {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func store(data: Data, preferredExtension: String, maxBytes: Int? = nil) throws -> CachedFile {
        try prepareStorage()

        let normalizedExtension = preferredExtension.hasPrefix(".")
            ? String(preferredExtension.dropFirst())
            : preferredExtension
        var fileURL = rootDirectory.appendingPathComponent(UUID().uuidString)
        if !normalizedExtension.isEmpty {
            fileURL.appendPathExtension(normalizedExtension)
        }

        try data.write(to: fileURL, options: [.atomic])
        try SensitiveFilePermissions.secureFile(at: fileURL)
        if let maxBytes {
            try prune(toMaxBytes: maxBytes, preserving: fileURL)
        }

        return CachedFile(fileURL: fileURL)
    }

    public func prune(toMaxBytes maxBytes: Int) throws {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return
        }
        try prepareStorage()
        try prune(toMaxBytes: maxBytes, preserving: nil)
    }

    public func totalBytes() throws -> Int {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return 0
        }
        try prepareStorage()

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )

        return try fileURLs.reduce(0) { total, fileURL in
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                return total
            }
            return total + (values.fileSize ?? 0)
        }
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return
        }

        try FileManager.default.removeItem(at: rootDirectory)
    }

    private func prune(toMaxBytes maxBytes: Int, preserving preservedFileURL: URL?) throws {
        guard maxBytes >= 0, FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return
        }

        var entries = try cachedFileEntries()
        var totalBytes = entries.reduce(0) { $0 + $1.byteCount }
        guard totalBytes > maxBytes else {
            return
        }

        entries.sort { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.fileURL.lastPathComponent < rhs.fileURL.lastPathComponent
            }
            return lhs.modifiedAt < rhs.modifiedAt
        }

        for entry in entries where totalBytes > maxBytes {
            if let preservedFileURL, entry.fileURL == preservedFileURL {
                continue
            }

            try FileManager.default.removeItem(at: entry.fileURL)
            totalBytes -= entry.byteCount
        }
    }

    private func prepareStorage() throws {
        try SensitiveFilePermissions.prepareDirectory(at: rootDirectory)
        try SensitiveFilePermissions.secureRegularFiles(in: rootDirectory)
    }

    private func cachedFileEntries() throws -> [CachedFileEntry] {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        )

        return try fileURLs.compactMap { fileURL in
            let values = try fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            )
            guard values.isRegularFile == true else {
                return nil
            }

            return CachedFileEntry(
                fileURL: fileURL,
                byteCount: values.fileSize ?? 0,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
    }
}

private struct CachedFileEntry {
    let fileURL: URL
    let byteCount: Int
    let modifiedAt: Date
}
