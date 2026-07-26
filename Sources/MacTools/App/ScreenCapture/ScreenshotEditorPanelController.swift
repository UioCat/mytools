// `ScreenshotEditorPanelController` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

import AppKit
import CoreGraphics
import MacToolsCore
import SwiftUI

/// 管理 `ScreenshotEditorPanelController` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
@MainActor
final class ScreenshotEditorPanelController {
    private var panel: NSPanel?

    /// 展示 `present` 对应的屏幕捕获系统集成界面或系统位置。
    func present(
        image: CGImage,
        selection: ScreenCaptureSelection,
        settings: ScreenCaptureSettings,
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) -> Bool {
        dismiss()

        let displayBounds = CGRect(origin: .zero, size: selection.displayFrame.size)
        let selectionFrame = selection.frame.offsetBy(
            dx: -selection.displayFrame.minX,
            dy: -selection.displayFrame.minY
        )
        let toolbarFrame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: selectionFrame,
            displayBounds: displayBounds
        )

        let rootView = ScreenshotEditorView(
            image: image,
            imageFrame: Self.swiftUIFrame(from: selectionFrame, in: displayBounds),
            toolbarFrame: Self.swiftUIFrame(from: toolbarFrame, in: displayBounds),
            settings: settings,
            onSettingsChange: onSettingsChange,
            onCopy: { [weak self] data in
                self?.dismiss()
                onCopy(data)
            },
            onCancel: { [weak self] in
                self?.dismiss()
                onCancel()
            }
        )
        let panel = ScreenshotEditorPanel(
            contentRect: selection.displayFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "截图编辑"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: rootView)
        panel.setFrame(selection.displayFrame, display: true)
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        return panel.isVisible
    }

    /// 取消或关闭 `dismiss` 对应的屏幕捕获系统集成流程，并清理临时状态。
    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// 计算并返回 `swiftUIFrame` 对应的屏幕捕获系统集成数据或状态结果。
    private static func swiftUIFrame(from appKitFrame: CGRect, in displayBounds: CGRect) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: displayBounds.height - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}

/// 管理 `ScreenshotEditorPanel` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
private final class ScreenshotEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
