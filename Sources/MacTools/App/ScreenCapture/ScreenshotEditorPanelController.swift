import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class ScreenshotEditorPanelController {
    private var panel: NSPanel?

    func present(
        image: CGImage,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()

        let rootView = ScreenshotEditorView(
            image: image,
            onCopy: { [weak self] data in
                self?.dismiss()
                onCopy(data)
            },
            onCancel: { [weak self] in
                self?.dismiss()
                onCancel()
            }
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "截图编辑"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: rootView)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 24
        panel.contentView?.layer?.masksToBounds = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
