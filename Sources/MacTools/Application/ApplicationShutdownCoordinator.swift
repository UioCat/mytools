import AppKit

/// 以可注入的关闭操作协调系统退出请求。
@MainActor
final class ApplicationShutdownCoordinator {
    private let stop: @MainActor () async -> Void
    private let flush: @MainActor () -> Void
    private let reply: @MainActor () -> Void
    private var shutdownTask: Task<Void, Never>?
    private var hasFinished = false

    init(
        stop: @escaping @MainActor () async -> Void,
        flush: @escaping @MainActor () -> Void,
        reply: @escaping @MainActor () -> Void
    ) {
        self.stop = stop
        self.flush = flush
        self.reply = reply
    }

    func requestTermination() -> NSApplication.TerminateReply {
        guard !hasFinished else { return .terminateNow }
        guard shutdownTask == nil else { return .terminateLater }
        shutdownTask = Task {
            await stop()
            flush()
            hasFinished = true
            reply()
            shutdownTask = nil
        }
        return .terminateLater
    }

    func waitForCompletion() async { await shutdownTask?.value }
}
