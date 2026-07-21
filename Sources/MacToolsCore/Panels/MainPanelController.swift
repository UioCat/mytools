import AppKit
import SwiftUI

enum MainPanelPositioningDecision: Equatable {
    case center
    case preserveCurrentFrame
}

enum MainPanelPositioningPolicy {
    static func decision(hasExistingPanel: Bool) -> MainPanelPositioningDecision {
        hasExistingPanel ? .preserveCurrentFrame : .center
    }
}

public final class MainPanelController {
    public static let windowStyleMask: NSWindow.StyleMask = [.borderless, .resizable]
    static let usesSystemWindowShadow = false
    static let windowCornerRadius = LiquidGlassCornerGeometry.windowRadius

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
        let positioningDecision = MainPanelPositioningPolicy.decision(
            hasExistingPanel: panel != nil
        )

        if panel == nil {
            let panel = EscapeDismissPanel(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: Self.windowStyleMask,
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
            // NSWindow shadows follow the rectangular window bounds, not the rounded SwiftUI glass shape.
            panel.hasShadow = Self.usesSystemWindowShadow
            panel.minSize = minimumSize
            panel.isMovableByWindowBackground = true
            panel.onDismiss = { [weak self] in
                self?.hide()
            }

            let hostingView = NSHostingView(rootView: rootView)
            panel.contentView = hostingView
            Self.configureRoundedBackingLayer(hostingView)
            if let frameView = hostingView.superview {
                // Liquid Glass can place its backdrop under the hosting view, so the AppKit frame must match too.
                Self.configureRoundedBackingLayer(frameView)
            }
            self.panel = panel
        }

        if positioningDecision == .center {
            panel?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func resize(to size: NSSize) {
        panel?.setContentSize(size)
        panel?.center()
    }

    static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

private final class EscapeDismissPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private let resolver = PanelKeyCommandResolver()

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

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
