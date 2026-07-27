// `ScreenshotEditorPanelController` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

import AppKit
import CoreGraphics
import MacToolsCore
import SwiftUI

/// 管理 `ScreenshotEditorPanelController` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
@MainActor
final class ScreenshotEditorPanelController {
    private var preparedView: NSView?

    /// 在不创建第二个窗口或改变应用焦点的前提下构造编辑内容并完成首次布局。
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
            onCopy: onCopy,
            onCancel: onCancel
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = displayBounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        preparedView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
    }

    /// 返回已预布局的透明编辑内容，由现有选区面板原位承载。
    func preparedContentView() -> NSView? {
        preparedView
    }

    /// 取消或关闭 `dismiss` 对应的屏幕捕获系统集成流程，并清理临时状态。
    func dismiss() {
        preparedView?.removeFromSuperview()
        preparedView = nil
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
