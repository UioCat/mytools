// `ScreenSelectionOverlayController` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

import AppKit
import MacToolsCore

/// 管理 `ScreenSelectionOverlayController` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
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
    private var isSelectionCommitted = false

    /// 在每块屏幕上创建不激活应用的全屏选区面板，并安装本地及全局 Escape 监听。
    func present(
        onSelection: @escaping (ScreenCaptureSelection, ScreenCaptureMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        dismiss()
        selectedMode = .default
        isSelectionCommitted = false
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
                guard let self,
                      !self.isSelectionCommitted,
                      let handler = self.onSelection else {
                    return
                }
                self.isSelectionCommitted = true
                let mode = self.selectedMode
                self.lockSelectionInteraction()
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
            panel.animationBehavior = .none
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
            // 全局按键监听依赖输入监控/辅助功能授权；本地监听仍覆盖应用收到按键的场景。
            guard event.keyCode == 53 else {
                return
            }
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    /// 取消或关闭 `dismiss` 对应的屏幕捕获系统集成流程，并清理临时状态。
    func dismiss() {
        removeModeToolbar()
        for panel in panels {
            panel.allowsKeyWindow = false
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
        isSelectionCommitted = false
    }

    /// 在当前选区面板内原位挂载编辑内容，保持窗口和遮罩层不变。
    func presentEditor(_ editorView: NSView, for selection: ScreenCaptureSelection) -> Bool {
        guard isSelectionCommitted,
              let panel = panels.first(where: {
                  ($0.contentView as? ScreenSelectionView)?.displayID == selection.displayID
              }),
              let selectionView = panel.contentView as? ScreenSelectionView else {
            return false
        }

        removeModeToolbar()
        selectionView.presentEditor(editorView)
        for candidate in panels where candidate !== panel {
            candidate.orderOut(nil)
        }
        selectionView.layoutSubtreeIfNeeded()
        selectionView.displayIfNeeded()
        panel.displayIfNeeded()
        panel.allowsKeyWindow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.makeKey()
        panel.displayIfNeeded()
        return panel.isVisible
            && panel.isKeyWindow
            && editorView.superview === selectionView
    }

    /// 将新的拖动屏幕设为唯一活动选区，并清除其他屏幕上的旧选择。
    private func prepareForNewSelection(from sourceView: ScreenSelectionView) {
        guard !isSelectionCommitted else {
            return
        }
        removeModeToolbar()
        showModeToolbar(in: sourceView)
        for panel in panels where panel.contentView !== sourceView {
            (panel.contentView as? ScreenSelectionView)?.clearSelection()
        }
    }

    /// 展示 `showModeToolbar` 对应的屏幕捕获系统集成界面或系统位置。
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

    /// 移除 `removeModeToolbar` 指定的屏幕捕获系统集成数据，并维护关联状态。
    private func removeModeToolbar() {
        modeToolbar?.removeFromSuperview()
        modeToolbar = nil
        modeControl = nil
    }

    /// 更新 `changeMode` 对应的交互状态，并保持当前选择或展示约束。
    @objc private func changeMode(_ sender: NSSegmentedControl) {
        guard !isSelectionCommitted else {
            sender.selectedSegment = selectedMode == .screenshot ? 0 : 1
            return
        }
        selectedMode = sender.selectedSegment == 1 ? .recording : .screenshot
    }

    /// 锁定已提交选区，保留当前视觉状态直到新表面已经置前。
    private func lockSelectionInteraction() {
        for panel in panels {
            (panel.contentView as? ScreenSelectionView)?.isInteractionLocked = true
        }
    }

    /// 判断 `cancel` 所描述的屏幕捕获系统集成条件是否成立。
    private func cancel() {
        let handler = onCancel
        dismiss()
        handler?()
    }

    /// 计算并返回 `displayID` 对应的屏幕捕获系统集成数据或状态结果。
    private static func displayID(for screen: NSScreen) -> UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }
}

/// 管理 `ScreenSelectionPanel` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
private final class ScreenSelectionPanel: NSPanel {
    var allowsKeyWindow = false

    override var canBecomeKey: Bool { allowsKeyWindow }
    override var canBecomeMain: Bool { false }
}

/// 管理 `ScreenSelectionView` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
private final class ScreenSelectionView: NSView {
    let displayID: UInt32
    let displayFrame: CGRect
    var onDragBegan: (() -> Void)?
    var onDragFinished: ((ScreenCaptureSelection, CGRect) -> Void)?
    var isInteractionLocked = false

    private var dragStart: CGPoint?
    private var currentPoint: CGPoint?
    private var completedSelectionFrame: CGRect?
    private var isEditing = false
    private weak var editorView: NSView?

    /// 创建 `ScreenSelectionView`，保存传入依赖并建立初始状态。
    init(displayID: UInt32, displayFrame: CGRect) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        super.init(frame: NSRect(origin: .zero, size: displayFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// 创建 `ScreenSelectionView`，保存传入依赖并建立初始状态。
    required init?(coder: NSCoder) {
        nil
    }

    /// 响应 `mouseDown` 对应的系统或界面回调，并同步当前交互状态。
    override func mouseDown(with event: NSEvent) {
        guard !isInteractionLocked else {
            return
        }
        dragStart = convert(event.locationInWindow, from: nil)
        currentPoint = dragStart
        completedSelectionFrame = nil
        onDragBegan?()
        needsDisplay = true
    }

    /// 响应 `mouseDragged` 对应的系统或界面回调，并同步当前交互状态。
    override func mouseDragged(with event: NSEvent) {
        guard !isInteractionLocked else {
            return
        }
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    /// 将面板局部选区换算为全局屏幕坐标，过滤过小区域后提交选择。
    override func mouseUp(with event: NSEvent) {
        guard !isInteractionLocked else {
            return
        }
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

        completedSelectionFrame = selection.displayRelativeFrame
        needsDisplay = true
        onDragFinished?(selection, selection.displayRelativeFrame)
    }

    /// 移除 `clearSelection` 指定的屏幕捕获系统集成数据，并维护关联状态。
    func clearSelection() {
        dragStart = nil
        currentPoint = nil
        completedSelectionFrame = nil
        needsDisplay = true
    }

    /// 在选区视图上叠加透明编辑内容，并继续复用当前遮罩和选区镂空。
    func presentEditor(_ editorView: NSView) {
        self.editorView?.removeFromSuperview()
        self.editorView = editorView
        isInteractionLocked = true
        isEditing = true
        editorView.frame = bounds
        editorView.autoresizingMask = [.width, .height]
        addSubview(editorView)
        needsDisplay = true
    }

    /// 在当前图形上下文中绘制 `draw` 指定的截图标注内容。
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

        guard !isEditing else {
            return
        }

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
        guard let frame = selectionFrame ?? completedSelectionFrame else {
            return nil
        }
        return frame.standardized.intersection(bounds).integral
    }
}
