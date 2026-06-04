public final class Logger {
    public private(set) var messages: [String] = []

    public init() {}

    public func info(_ message: String) {
        messages.append("INFO \(message)")
    }

    public func error(_ message: String) {
        messages.append("ERROR \(message)")
    }
}
