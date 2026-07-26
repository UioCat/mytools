// `Logger` 的基础设施工具实现。
// 提供日志和敏感文件权限等通用能力，不承载业务流程。

import Foundation

/// 管理 `Logger` 在基础设施工具中的生命周期、依赖和可变状态。
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

    /// 创建 `Logger`，保存传入依赖并建立初始状态。
    public init(debugLogDirectory: URL? = nil) {
        self.configuredDebugLogDirectory = debugLogDirectory
    }

    /// 计算并返回 `info` 对应的基础设施工具数据或状态结果。
    public func info(_ message: String) {
        record(level: "INFO", message: message)
    }

    /// 计算并返回 `error` 对应的基础设施工具数据或状态结果。
    public func error(_ message: String) {
        record(level: "ERROR", message: message)
    }

    /// 提交 `flush` 对应的基础设施工具状态，并记录后续流程所需的进度。
    public func flush() {
        Self.fileWriteQueue.sync {}
    }

    /// 保存 `record` 接收的基础设施工具数据，并保持既有持久化约束。
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

    /// 保存 `writeToDebugLog` 接收的基础设施工具数据，并保持既有持久化约束。
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

    /// 构造并返回 `defaultDebugLogDirectory` 所描述的基础设施工具对象。
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
