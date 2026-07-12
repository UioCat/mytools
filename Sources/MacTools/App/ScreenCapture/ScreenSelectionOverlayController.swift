import AppKit
import MacToolsCore

@MainActor
final class ScreenSelectionOverlayController {
    private var panels: [ScreenSelectionPanel] = []
    private weak var modeToolbar: NSView?
    private var pendingSelection: ScreenCaptureSelection?
    private var onMode: ((ScreenCaptureSelection, ScreenCaptureMode) -> Void)?
    private var onCancel: (() -> Void)?
    private var escapeEventMonitor: Any?
    private var globalEscapeEventMonitor: Any?

    func present(
        onMode: @escaping (ScreenCaptureSelection, ScreenCaptureMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()
        self.onMode = onMode
        self.onCancel = onCancel

        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else {
                continue
            }

            let selectionView = ScreenSelectionView(displayID: displayID, displayFrame: screen.frame)
            selectionView.onDragBegan = { [weak self, weak selectionView] in
                guard let self, let selectionView else {
                    return
                }
                self.prepareForNewSelection(from: selectionView)
            }
            selectionView.onDragFinished = { [weak self, weak selectionView] selection, localFrame in
                guard let self, let selectionView else {
                    return
                }
                self.showModeToolbar(for: selection, in: selectionView, selectionFrame: localFrame)
            }

            let panel = ScreenSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(screen.frame, display: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = selectionView
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        escapeEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.cancel()
                return nil
            }
            return event
        }
        globalEscapeEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else {
                return
            }
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func dismiss() {
        removeModeToolbar()
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
        pendingSelection = nil
        if let escapeEventMonitor {
            NSEvent.removeMonitor(escapeEventMonitor)
        }
        escapeEventMonitor = nil
        if let globalEscapeEventMonitor {
            NSEvent.removeMonitor(globalEscapeEventMonitor)
        }
        globalEscapeEventMonitor = nil
        onMode = nil
        onCancel = nil
    }

    private func prepareForNewSelection(from sourceView: ScreenSelectionView) {
        removeModeToolbar()
        pendingSelection = nil
        for panel in panels where panel.contentView !== sourceView {
            (panel.contentView as? ScreenSelectionView)?.clearSelection()
        }
    }

    private func showModeToolbar(
        for selection: ScreenCaptureSelection,
        in selectionView: ScreenSelectionView,
        selectionFrame: CGRect
    ) {
        removeModeToolbar()
        pendingSelection = selection

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true

        let screenshotButton = makeToolbarButton(
            title: "截图",
            imageName: "camera",
            action: #selector(selectScreenshot)
        )
        let recordingButton = makeToolbarButton(
            title: "录屏",
            imageName: "record.circle",
            action: #selector(selectRecording)
        )
        let stack = NSStackView(views: [screenshotButton, recordingButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        effectView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        let size = NSSize(width: 168, height: 44)
        let x = min(max(selectionFrame.maxX - size.width, 12), selectionView.bounds.maxX - size.width - 12)
        let preferredY = selectionFrame.minY - size.height - 10
        let y = preferredY >= 12 ? preferredY : min(selectionFrame.maxY + 10, selectionView.bounds.maxY - size.height - 12)
        effectView.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        selectionView.addSubview(effectView)
        modeToolbar = effectView
    }

    private func makeToolbarButton(title: String, imageName: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.bezelStyle = .texturedRounded
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel(title)
        return button
    }

    private func removeModeToolbar() {
        modeToolbar?.removeFromSuperview()
        modeToolbar = nil
    }

    @objc private func selectScreenshot() {
        select(mode: .screenshot)
    }

    @objc private func selectRecording() {
        select(mode: .recording)
    }

    private func select(mode: ScreenCaptureMode) {
        guard let selection = pendingSelection, let handler = onMode else {
            return
        }
        dismiss()
        handler(selection, mode)
    }

    private func cancel() {
        let handler = onCancel
        dismiss()
        handler?()
    }

    private static func displayID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

private final class ScreenSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScreenSelectionView: NSView {
    let displayID: UInt32
    let displayFrame: CGRect
    var onDragBegan: (() -> Void)?
    var onDragFinished: ((ScreenCaptureSelection, CGRect) -> Void)?

    private var dragStart: CGPoint?
    private var currentPoint: CGPoint?
    private var completedSelectionFrame: CGRect?

    init(displayID: UInt32, displayFrame: CGRect) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        super.init(frame: NSRect(origin: .zero, size: displayFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        currentPoint = dragStart
        completedSelectionFrame = nil
        onDragBegan?()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        defer {
            dragStart = nil
            currentPoint = nil
        }

        guard let rawFrame = selectionFrame else {
            needsDisplay = true
            return
        }
        let globalFrame = rawFrame.offsetBy(dx: displayFrame.minX, dy: displayFrame.minY)
        let selection = ScreenCaptureSelection(
            displayID: displayID,
            displayFrame: displayFrame,
            rawSelectionFrame: globalFrame
        )
        guard selection.isValid else {
            needsDisplay = true
            return
        }

        completedSelectionFrame = rawFrame.standardized
        needsDisplay = true
        onDragFinished?(selection, selection.frame.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY))
    }

    func clearSelection() {
        dragStart = nil
        currentPoint = nil
        completedSelectionFrame = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        guard let selectionFrame = visibleSelectionFrame else {
            return
        }

        let rect = selectionFrame.standardized
        guard !rect.isEmpty else {
            return
        }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(rect)
        context.restoreGState()

        NSColor.white.withAlphaComponent(0.92).setStroke()
        let outerPath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        outerPath.lineWidth = 1
        outerPath.stroke()

        NSColor.systemBlue.setStroke()
        let innerPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2)
        innerPath.lineWidth = 2
        innerPath.stroke()
    }

    private var selectionFrame: CGRect? {
        guard let dragStart, let currentPoint else {
            return nil
        }
        return CGRect(
            x: dragStart.x,
            y: dragStart.y,
            width: currentPoint.x - dragStart.x,
            height: currentPoint.y - dragStart.y
        )
    }

    private var visibleSelectionFrame: CGRect? {
        selectionFrame ?? completedSelectionFrame
    }
}
