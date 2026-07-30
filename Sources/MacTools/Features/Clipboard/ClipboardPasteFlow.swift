// 剪贴板面板自动粘贴的主线程时序协调。
// 复制完成后才检查权限、关闭面板并激活目标应用。

import Foundation
import MacToolsCore

@MainActor
struct ClipboardPasteFlow {
    private let copy: (ClipboardItem) async throws -> Void
    private let canPostPasteEvent: () -> Bool
    private let showPermissionAlert: () -> Void
    private let hidePanel: () -> Void
    private let activateAndPaste: () -> Void
    private let reportError: (Error) -> Void

    init(
        copy: @escaping (ClipboardItem) async throws -> Void,
        canPostPasteEvent: @escaping () -> Bool,
        showPermissionAlert: @escaping () -> Void,
        hidePanel: @escaping () -> Void,
        activateAndPaste: @escaping () -> Void,
        reportError: @escaping (Error) -> Void
    ) {
        self.copy = copy
        self.canPostPasteEvent = canPostPasteEvent
        self.showPermissionAlert = showPermissionAlert
        self.hidePanel = hidePanel
        self.activateAndPaste = activateAndPaste
        self.reportError = reportError
    }

    func run(_ item: ClipboardItem) async {
        do {
            try await copy(item)
        } catch {
            reportError(error)
            return
        }

        guard canPostPasteEvent() else {
            showPermissionAlert()
            return
        }

        hidePanel()
        activateAndPaste()
    }
}
