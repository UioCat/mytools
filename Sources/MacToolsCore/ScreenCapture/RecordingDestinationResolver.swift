import Foundation

public enum RecordingDestinationError: Error, Equatable {
    case directoryUnavailable(URL)
}

public struct RecordingDestinationResolver {
    public let directory: URL
    public let now: Date
    public let timeZone: TimeZone

    public init(directory: URL, now: Date = .now, timeZone: TimeZone = .current) {
        self.directory = directory
        self.now = now
        self.timeZone = timeZone
    }

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
