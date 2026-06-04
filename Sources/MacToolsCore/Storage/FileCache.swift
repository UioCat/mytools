import Foundation

public struct CachedFile: Equatable {
    public let fileURL: URL
}

public final class FileCache {
    private let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func store(data: Data, preferredExtension: String) throws -> CachedFile {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let normalizedExtension = preferredExtension.hasPrefix(".")
            ? String(preferredExtension.dropFirst())
            : preferredExtension
        var fileURL = rootDirectory.appendingPathComponent(UUID().uuidString)
        if !normalizedExtension.isEmpty {
            fileURL.appendPathExtension(normalizedExtension)
        }

        try data.write(to: fileURL, options: [.atomic])
        return CachedFile(fileURL: fileURL)
    }

    public func totalBytes() throws -> Int {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return 0
        }

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
}
