// 日志的内存记录、后台写入和磁盘轮转使用独立预算。
import Foundation

public final class Logger: @unchecked Sendable {
    struct Limits: Sendable {
        var messageCount = 1_024
        var messageBytes = 1_024 * 1_024
        var lineBytes = 16 * 1_024
        var pendingCount = 512
        var pendingBytes = 1_024 * 1_024
        var fileBytes = 1_024 * 1_024
        var archiveCount = 3
    }
    private static let fileWriteQueue = DispatchQueue(label: "com.mactools.debug-log-writer", qos: .utility)
    private let configuredDebugLogDirectory: URL?
    private let limits: Limits
    private let write: (@Sendable (Data) throws -> Void)?
    private let messagesLock = NSLock()
    private var recordedMessages: [String] = []
    private var messageBytes = 0
    private var pending: [Data] = []
    private var pendingBytes = 0
    private var pendingCount = 0
    private var writing = false
    private var dropped = 0
    // 只在文件写入队列访问；首次写入同时收紧升级前遗留文件的大小和权限。
    private var didPrepareLogFiles = false

    public var messages: [String] { messagesLock.withLock { recordedMessages } }
    /// 仅统计未能接受或写入文件的日志；已接受队列不会因新日志而被淘汰。
    public var droppedFileMessageCount: Int { messagesLock.withLock { dropped } }
    var pendingFileBudget: (count: Int, bytes: Int) {
        messagesLock.withLock { (pendingCount, pendingBytes) }
    }
    public convenience init(debugLogDirectory: URL? = nil) {
        self.init(debugLogDirectory: debugLogDirectory, limits: Limits())
    }
    init(debugLogDirectory: URL?, limits: Limits, write: (@Sendable (Data) throws -> Void)? = nil) {
        self.configuredDebugLogDirectory = debugLogDirectory
        var safe = limits
        safe.messageCount = max(1, safe.messageCount)
        safe.messageBytes = max(64, safe.messageBytes)
        safe.pendingCount = max(1, safe.pendingCount)
        safe.pendingBytes = max(64, safe.pendingBytes)
        safe.fileBytes = max(64, safe.fileBytes)
        safe.lineBytes = max(16, min(safe.lineBytes, safe.messageBytes, safe.pendingBytes - 32, safe.fileBytes - 32))
        safe.archiveCount = max(0, safe.archiveCount)
        self.limits = safe
        self.write = write
    }
    public func info(_ message: String) { record(level: "INFO", message: message) }
    public func error(_ message: String) { record(level: "ERROR", message: message) }
    public func flush() { Self.fileWriteQueue.sync {} }

    private func record(level: String, message: String) {
        let raw = "\(level) \(message)"
        let line: String
        if raw.utf8.count > limits.lineBytes {
            line = String(decoding: raw.utf8.prefix(limits.lineBytes - 16), as: UTF8.self) + " [truncated]"
        } else { line = raw }
        let data = Data("\(Date().timeIntervalSince1970) \(line)\n".utf8)
        let shouldSchedule = messagesLock.withLock {
            recordedMessages.append(line)
            messageBytes += line.utf8.count
            while recordedMessages.count > limits.messageCount || messageBytes > limits.messageBytes {
                messageBytes -= recordedMessages.removeFirst().utf8.count
            }
            guard pendingCount < limits.pendingCount, data.count <= limits.pendingBytes - pendingBytes else {
                dropped += 1
                return false
            }
            pending.append(data)
            pendingCount += 1
            pendingBytes += data.count
            guard !writing else { return false }
            writing = true
            return true
        }
        NSLog("%@", line)
        if shouldSchedule {
            Self.fileWriteQueue.async { [self] in drainPending() }
        }
    }
    private func drainPending() {
        while true {
            let batch = messagesLock.withLock {
                guard !pending.isEmpty else { writing = false; return [Data]() }
                let batch = Array(pending.prefix(32))
                pending.removeFirst(batch.count)
                return batch
            }
            guard !batch.isEmpty else { return }
            for data in batch {
                do {
                    if let write { try write(data) }
                    else {
                        try Self.writeToDebugLog(data, debugLogDirectory: configuredDebugLogDirectory,
                                                limits: limits, prepareExistingFiles: !didPrepareLogFiles)
                        didPrepareLogFiles = true
                    }
                } catch {
                    messagesLock.withLock { dropped += 1 }
                    NSLog("ERROR debug log write failed: %@", String(reflecting: type(of: error)))
                }
                messagesLock.withLock {
                    pendingBytes -= data.count
                    pendingCount -= 1
                }
            }
        }
    }
    private static func writeToDebugLog(
        _ data: Data, debugLogDirectory: URL?, limits: Limits, prepareExistingFiles: Bool
    ) throws {
        let directory = try debugLogDirectory ?? defaultDebugLogDirectory()
        try SensitiveFilePermissions.prepareDirectory(at: directory)
        let manager = FileManager.default
        let file = directory.appendingPathComponent("debug.log")
        if prepareExistingFiles {
            for index in 0...limits.archiveCount {
                let candidate = directory.appendingPathComponent(index == 0 ? "debug.log" : "debug.log.\(index)")
                guard manager.fileExists(atPath: candidate.path) else { continue }
                let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                try SensitiveFilePermissions.secureFile(at: candidate)
                let handle = try FileHandle(forUpdating: candidate)
                defer { try? handle.close() }
                let size = try handle.seekToEnd()
                if size > limits.fileBytes {
                    try handle.seek(toOffset: size - UInt64(limits.fileBytes))
                    let tail = try handle.read(upToCount: limits.fileBytes) ?? Data()
                    try handle.seek(toOffset: 0)
                    try handle.write(contentsOf: tail)
                    try handle.truncate(atOffset: UInt64(tail.count))
                }
            }
        }
        let size = (try? manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > limits.fileBytes - data.count {
            if limits.archiveCount > 0 {
                let oldest = directory.appendingPathComponent("debug.log.\(limits.archiveCount)")
                if manager.fileExists(atPath: oldest.path) { try manager.removeItem(at: oldest) }
                if limits.archiveCount > 1 {
                    for index in stride(from: limits.archiveCount - 1, through: 1, by: -1) {
                        let source = directory.appendingPathComponent("debug.log.\(index)")
                        if manager.fileExists(atPath: source.path) {
                            try manager.moveItem(at: source, to: directory.appendingPathComponent("debug.log.\(index + 1)"))
                        }
                    }
                }
                try SensitiveFilePermissions.secureFile(at: file)
                try manager.moveItem(at: file, to: directory.appendingPathComponent("debug.log.1"))
            } else { try manager.removeItem(at: file) }
        }
        if !manager.fileExists(atPath: file.path) {
            guard manager.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try SensitiveFilePermissions.secureFile(at: file)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
    private static func defaultDebugLogDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MacTools", isDirectory: true)
    }
}
