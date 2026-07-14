import AppKit
import CoreGraphics
import MacToolsCore
import SwiftUI

@MainActor
final class ScreenshotEditorPanelController {
    private var panel: NSPanel?

    func present(
        image: CGImage,
        selection: ScreenCaptureSelection,
        settings: ScreenCaptureSettings,
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
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
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private static func swiftUIFrame(from appKitFrame: CGRect, in displayBounds: CGRect) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: displayBounds.height - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}

private final class ScreenshotEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
