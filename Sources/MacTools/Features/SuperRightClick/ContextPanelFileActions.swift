import Foundation
import Combine
import MacToolsCore

enum ContextPanelFileActionEffect: Equatable, Sendable {
    case none
    case copyPath(String)
    case reveal(URL)
}

/// 文件服务由此执行器独占；主 Actor 只接收执行结果并处理系统展示。
final class ContextPanelFileActionWorker: @unchecked Sendable {
    private let service: FileActionService
    private let queue = DispatchQueue(label: "MacTools context file actions", qos: .userInitiated)

    init(service: FileActionService) { self.service = service }

    @MainActor
    func perform(_ action: SuperPanelActionID, item: ClipboardItem) async throws -> ContextPanelFileActionEffect {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try execute(action, item: item)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// 仅由专用串行队列调用，避免不可发送的文件服务跨线程并发访问。
    private func execute(_ action: SuperPanelActionID, item: ClipboardItem) throws -> ContextPanelFileActionEffect {
        switch action {
        case .copyPath:
            guard let path = item.originalPath else { throw FileActionError.missingPath }
            return .copyPath(path)
        case .createNewFile:
            return .reveal(try service.createNewFile(in: item))
        case .openTerminal:
            guard let path = item.originalPath else { throw FileActionError.missingPath }
            try service.openTerminal(at: path)
        case .revealInFinder:
            guard let path = item.originalPath else { throw FileActionError.missingPath }
            return .reveal(URL(fileURLWithPath: path))
        case .openClaudeCode, .openClaudeCodeSkipConfirmation:
            guard let path = item.originalPath else { throw FileActionError.missingPath }
            try service.openExternalApplication(named: "Claude", at: path)
        default:
            throw FileActionError.missingPath
        }
        return .none
    }
}

@MainActor
final class ContextPanelFileActionModel: ObservableObject {
    @Published private(set) var isExecuting = false
    @Published private(set) var failureMessage: String?
    private var generation = UUID()

    func reset() { generation = UUID(); isExecuting = false; failureMessage = nil }

    func perform(
        _ action: SuperPanelActionID,
        execute: () async throws -> ContextPanelFileActionEffect,
        isCurrent: () -> Bool,
        onSuccess: (ContextPanelFileActionEffect) -> Void,
        logFailure: (String) -> Void
    ) async {
        guard !isExecuting, isCurrent(), !Task.isCancelled else { return }
        let requestGeneration = generation
        isExecuting = true
        failureMessage = nil
        defer { if generation == requestGeneration { isExecuting = false } }
        do {
            let effect = try await execute()
            guard generation == requestGeneration, isCurrent(), !Task.isCancelled else { return }
            onSuccess(effect)
        } catch {
            guard generation == requestGeneration, isCurrent(), !Task.isCancelled else { return }
            logFailure(String(reflecting: type(of: error)))
            failureMessage = Self.failureMessage(for: action)
        }
    }

    private static func failureMessage(for action: SuperPanelActionID) -> String {
        switch action {
        case .createNewFile: return "无法新建文件，请检查目录或系统权限后重试。"
        case .openTerminal: return "无法在终端打开，请检查目录或系统权限后重试。"
        case .openClaudeCode, .openClaudeCodeSkipConfirmation: return "无法打开 Claude，请检查应用是否安装后重试。"
        case .copyPath: return "无法复制路径，请重新选择文件后重试。"
        case .revealInFinder: return "无法在访达显示，请重新选择文件后重试。"
        default: return "操作失败，请重试。"
        }
    }
}
