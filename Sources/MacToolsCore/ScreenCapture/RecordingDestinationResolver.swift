// `RecordingDestinationResolver` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import Foundation

/// 描述 `RecordingDestinationError` 在截图录屏核心领域中可取的状态、选项或错误。
public enum RecordingDestinationError: Error, Equatable {
    case directoryUnavailable(URL)
}

/// 封装 `RecordingDestinationResolver` 在截图录屏核心领域中的值语义和相关操作。
public struct RecordingDestinationResolver {
    public let directory: URL
    public let now: Date
    public let timeZone: TimeZone

    /// 创建 `RecordingDestinationResolver`，保存传入依赖并建立初始状态。
    public init(directory: URL, now: Date = .now, timeZone: TimeZone = .current) {
        self.directory = directory
        self.now = now
        self.timeZone = timeZone
    }

    /// 计算并返回 `nextURL` 对应的截图录屏核心领域数据或状态结果。
    public func nextURL(fileManager: FileManager = .default) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RecordingDestinationError.directoryUnavailable(directory)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stem = "MacTools Recording \(formatter.string(from: now))"

        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = directory.appendingPathComponent("\(stem)\(suffix).mp4")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
