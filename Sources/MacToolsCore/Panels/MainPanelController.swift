import AppKit
import SwiftUI

public final class MainPanelController {
    private var panel: NSPanel?
    private let rootView: AnyView
    private let initialSize: NSSize
    private let minimumSize: NSSize

    public init<Content: View>(
        initialSize: NSSize = NSSize(width: 900, height: 620),
        minimumSize: NSSize = NSSize(width: 720, height: 480),
        rootView: Content
    ) {
        self.initialSize = initialSize
        self.minimumSize = minimumSize
        self.rootView = AnyView(rootView)
    }

    public func show() {
        if panel == nil {
            let panel = EscapeDismissPanel(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.titled, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.minSize = minimumSize
            panel.isMovableByWindowBackground = true
            panel.onDismiss = { [weak self] in
                self?.hide()
            }

            let hostingView = NSHostingView(rootView: rootView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hostingView
            self.panel = panel
        }

        panel?.center()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
    }
}

private final class EscapeDismissPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private let resolver = PanelKeyCommandResolver()

    override func keyDown(with event: NSEvent) {
        if resolver.command(forKeyCode: event.keyCode) == .dismiss {
            onDismiss?()
            return
        }

        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}
