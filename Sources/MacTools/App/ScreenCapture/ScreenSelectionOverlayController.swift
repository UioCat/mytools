import AppKit
import MacToolsCore

@MainActor
final class ScreenSelectionOverlayController {
    private var panels: [ScreenSelectionPanel] = []
    private weak var modeToolbar: NSView?
    private weak var modeControl: NSSegmentedControl?
    private var selectedMode: ScreenCaptureMode = .default
    private var onSelection: ((ScreenCaptureSelection, ScreenCaptureMode) -> Void)?
    private var onCancel: (() -> Void)?
    private var escapeEventMonitor: Any?
    private var globalEscapeEventMonitor: Any?

    func present(
        onSelection: @escaping (ScreenCaptureSelection, ScreenCaptureMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()
        selectedMode = .default
        self.onSelection = onSelection
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
            selectionView.onDragFinished = { [weak self] selection, _ in
                guard let self, let handler = self.onSelection else {
                    return
                }
                let mode = self.selectedMode
                self.dismiss()
                handler(selection, mode)
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

        let mouseLocation = NSEvent.mouseLocation
        let preferredView = panels
            .compactMap { $0.contentView as? ScreenSelectionView }
            .first(where: { $0.displayFrame.contains(mouseLocation) })
            ?? panels.first?.contentView as? ScreenSelectionView
        if let preferredView {
            showModeToolbar(in: preferredView)
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
        if let escapeEventMonitor {
            NSEvent.removeMonitor(escapeEventMonitor)
        }
        escapeEventMonitor = nil
        if let globalEscapeEventMonitor {
            NSEvent.removeMonitor(globalEscapeEventMonitor)
        }
        globalEscapeEventMonitor = nil
        onSelection = nil
        onCancel = nil
    }

    private func prepareForNewSelection(from sourceView: ScreenSelectionView) {
        removeModeToolbar()
        showModeToolbar(in: sourceView)
        for panel in panels where panel.contentView !== sourceView {
            (panel.contentView as? ScreenSelectionView)?.clearSelection()
        }
    }

    private func showModeToolbar(in selectionView: ScreenSelectionView) {
        removeModeToolbar()

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true

        let modeControl = NSSegmentedControl(
            labels: ["截图", "录屏"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(changeMode(_:))
        )
        modeControl.selectedSegment = selectedMode == .screenshot ? 0 : 1
        modeControl.setImage(
            NSImage(systemSymbolName: "camera", accessibilityDescription: "截图"),
            forSegment: 0
        )
        modeControl.setImage(
            NSImage(systemSymbolName: "record.circle", accessibilityDescription: "录屏"),
            forSegment: 1
        )
        modeControl.setWidth(88, forSegment: 0)
        modeControl.setWidth(88, forSegment: 1)
        modeControl.setAccessibilityLabel("截图或录屏")
        effectView.addSubview(modeControl)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeControl.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            modeControl.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            modeControl.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 7),
            modeControl.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -7)
        ])

        effectView.frame = ScreenCaptureOverlayLayout.modeToolbarFrame(displayBounds: selectionView.bounds)
        selectionView.addSubview(effectView)
        modeToolbar = effectView
        self.modeControl = modeControl
    }

    private func removeModeToolbar() {
        modeToolbar?.removeFromSuperview()
        modeToolbar = nil
        modeControl = nil
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        selectedMode = sender.selectedSegment == 1 ? .recording : .screenshot
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
