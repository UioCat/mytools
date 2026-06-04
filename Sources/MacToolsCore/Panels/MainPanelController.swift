import AppKit
import SwiftUI

public final class MainPanelController {
    private var panel: NSPanel?
    private let rootView: AnyView

    public init<Content: View>(rootView: Content) {
        self.rootView = AnyView(rootView)
    }

    public func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.contentView = NSHostingView(rootView: rootView)
            self.panel = panel
        }

        panel?.center()
        panel?.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }
}
