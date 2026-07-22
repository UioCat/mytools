import Foundation

public final class Logger: @unchecked Sendable {
    private static let fileWriteQueue = DispatchQueue(
        label: "com.mactools.debug-log-writer",
        qos: .utility
    )
    private let configuredDebugLogDirectory: URL?
    private let messagesLock = NSLock()
    private var recordedMessages: [String] = []

    public var messages: [String] {
        messagesLock.lock()
        defer { messagesLock.unlock() }
        return recordedMessages
    }

    public init(debugLogDirectory: URL? = nil) {
        self.configuredDebugLogDirectory = debugLogDirectory
    }

    public func info(_ message: String) {
        record(level: "INFO", message: message)
    }

    public func error(_ message: String) {
        record(level: "ERROR", message: message)
    }

    public func flush() {
        Self.fileWriteQueue.sync {}
    }

    private func record(level: String, message: String) {
        let line = "\(level) \(message)"
        messagesLock.lock()
        recordedMessages.append(line)
        messagesLock.unlock()
        NSLog("%@", line)
        let debugLogDirectory = configuredDebugLogDirectory
        Self.fileWriteQueue.async {
            Self.writeToDebugLog(line, debugLogDirectory: debugLogDirectory)
        }
    }

    private static func writeToDebugLog(_ line: String, debugLogDirectory: URL?) {
        guard let data = "\(Date()) \(line)\n".data(using: .utf8) else {
            return
        }

        do {
            let directory = try debugLogDirectory ?? defaultDebugLogDirectory()
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
