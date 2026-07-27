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

    /// 在不改变窗口层级和应用焦点的前提下构造编辑器并完成首次布局。
    func prepare(
        image: CGImage,
        selection: ScreenCaptureSelection,
        settings: ScreenCaptureSettings,
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        let displayBounds = CGRect(origin: .zero, size: selection.displayFrame.size)
        let selectionFrame = selection.displayRelativeFrame
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
        panel.animationBehavior = .none
        panel.level = .screenSaver
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: rootView)
        panel.setFrame(selection.displayFrame, display: true)
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        panel.displayIfNeeded()
    }

    /// 将准备好的编辑器置前，再同步替换仍可见的选区层并获取键盘焦点。
    func presentPrepared(replaceVisibleSurface: () -> Void) -> Bool {
        guard let panel else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        guard panel.isVisible else {
            return false
        }
        replaceVisibleSurface()
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
