import Foundation

public final class Logger {
    private static let fileLock = NSLock()
    private let configuredDebugLogDirectory: URL?
    public private(set) var messages: [String] = []

    public init(debugLogDirectory: URL? = nil) {
        self.configuredDebugLogDirectory = debugLogDirectory
    }

    public func info(_ message: String) {
        record(level: "INFO", message: message)
    }

    public func error(_ message: String) {
        record(level: "ERROR", message: message)
    }

    private func record(level: String, message: String) {
        let line = "\(level) \(message)"
        messages.append(line)
        NSLog("%@", line)
        writeToDebugLog(line)
    }

    private func writeToDebugLog(_ line: String) {
        guard let data = "\(Date()) \(line)\n".data(using: .utf8) else {
            return
        }

        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }

        do {
            let directory = try configuredDebugLogDirectory ?? Self.defaultDebugLogDirectory()
            try SensitiveFilePermissions.prepareDirectory(at: directory)
            let fileURL = directory.appendingPathComponent("debug.log")

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            try SensitiveFilePermissions.secureFile(at: fileURL)

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            NSLog("ERROR debug log write failed %@", String(describing: error))
        }
    }

    private static func defaultDebugLogDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("MacTools", isDirectory: true)
    }
}
