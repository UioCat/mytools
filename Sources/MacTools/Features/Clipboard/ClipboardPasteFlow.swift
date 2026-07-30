// 剪贴板面板自动粘贴的主线程时序协调。
// 复制完成后才检查权限、关闭面板并激活目标应用。

import Foundation
import MacToolsCore

@MainActor
final class ClipboardPasteFlow {
    private let copy: (
        ClipboardItem,
        () throws -> Void
    ) async throws -> Void
    private let canPostPasteEvent: () -> Bool
    private let showPermissionAlert: () -> Void
    private let hidePanel: () -> Void
    private let reportError: (Error) -> Void
    private var generation = 0

    init(
        copy: @escaping (
            ClipboardItem,
            () throws -> Void
        ) async throws -> Void,
        canPostPasteEvent: @escaping () -> Bool,
        showPermissionAlert: @escaping () -> Void,
        hidePanel: @escaping () -> Void,
        reportError: @escaping (Error) -> Void
    ) {
        self.copy = copy
        self.canPostPasteEvent = canPostPasteEvent
        self.showPermissionAlert = showPermissionAlert
        self.hidePanel = hidePanel
        self.reportError = reportError
    }

    /// 取消旧任务、推进请求代次，并把激活目标作为当前请求的不可变快照。
    func start<T>(
        _ item: ClipboardItem,
        target: T,
        replacing previousTask: Task<Void, Never>?,
        activateAndPaste: @escaping (T) -> Void
    ) -> Task<Void, Never> {
        previousTask?.cancel()
        generation += 1
        let generation = generation
        return Task { @MainActor [weak self] in
            await self?.run(
                item,
                generation: generation,
                target: target,
                activateAndPaste: activateAndPaste
            )
        }
    }

    private func run<T>(
        _ item: ClipboardItem,
        generation: Int,
        target: T,
        activateAndPaste: (T) -> Void
    ) async {
        let isCurrent = { [weak self] in
            !Task.isCancelled && self?.generation == generation
        }
        let validateCurrent = { [weak self] in
            guard !Task.isCancelled, self?.generation == generation else {
                throw CancellationError()
            }
        }

        do {
            try validateCurrent()
            try await copy(item, validateCurrent)
            try validateCurrent()
        } catch is CancellationError {
            return
        } catch {
            reportError(error)
            return
        }

        guard canPostPasteEvent() else {
            guard isCurrent() else { return }
            showPermissionAlert()
            return
        }

        guard isCurrent() else { return }
        hidePanel()
        guard isCurrent() else { return }
        activateAndPaste(target)
    }
}
