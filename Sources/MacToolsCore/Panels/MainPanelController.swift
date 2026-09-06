// `MainPanelController` 的面板领域实现。
// 负责窗口外观和交互策略，不持久化业务数据。

import AppKit
import QuartzCore
import SwiftUI

/// 描述 `MainPanelPositioningDecision` 在面板领域中可取的状态、选项或错误。
enum MainPanelPositioningDecision: Equatable {
    case center
    case preserveCurrentFrame
}

/// 描述 `MainPanelPositioningPolicy` 在面板领域中可取的状态、选项或错误。
enum MainPanelPositioningPolicy {
    /// 根据输入特征判定 `decision` 对应的面板领域分类或处理决策。
    static func decision(hasExistingPanel: Bool) -> MainPanelPositioningDecision {
        hasExistingPanel ? .preserveCurrentFrame : .center
    }
}

/// 管理 `MainPanelController` 在面板领域中的生命周期、依赖和可变状态。
@MainActor
public final class MainPanelController {
    // 保留原生边框的窗口级命中与外侧缩放容错，标题栏内容由下方配置隐藏。
    public static let windowStyleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable]
    static let usesSystemWindowShadow = false
    static let windowCornerRadius = LiquidGlassCornerGeometry.windowRadius

    private var panel: NSPanel?
    private let rootView: AnyView
    private let initialSize: NSSize
    private let minimumSize: NSSize

    /// 创建 `MainPanelController`，保存传入依赖并建立初始状态。
    public init<Content: View>(
        initialSize: NSSize = NSSize(width: 900, height: 620),
        minimumSize: NSSize = NSSize(width: 720, height: 480),
        rootView: Content
    ) {
        self.initialSize = initialSize
        self.minimumSize = minimumSize
        self.rootView = AnyView(rootView)
    }

    /// 展示 `show` 对应的面板领域界面或系统位置。
    public func show() {
        let positioningDecision = MainPanelPositioningPolicy.decision(
            hasExistingPanel: panel != nil
        )

        if panel == nil {
            let panel = MainPanelWindow(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: Self.windowStyleMask,
                backing: .buffered,
                defer: false
            )
            Self.configureWindowChrome(panel)
            panel.minSize = minimumSize
            panel.isMovableByWindowBackground = true
            panel.onDismiss = { [weak self] in
                self?.hide()
            }

            let hostingView = MainPanelHostingView(rootView: rootView)
            panel.contentView = hostingView
            Self.configureHostingView(hostingView)
            if let frameView = hostingView.superview {
                // Liquid Glass 可能把背板放在 hosting view 下方，因此 AppKit frame 也必须保持一致。
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

    /// 取消或关闭 `hide` 对应的面板领域流程，并清理临时状态。
    public func hide() {
        panel?.orderOut(nil)
    }

    /// 更新 `resize` 对应的交互状态，并保持当前选择或展示约束。
    public func resize(to size: NSSize) {
        panel?.setContentSize(size)
        panel?.center()
    }

    /// 原生窗口框架负责鼠标命中，玻璃表面不显示系统标题栏和矩形阴影。
    static func configureWindowChrome(_ panel: NSPanel) {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // NSWindow 阴影跟随矩形窗口边界，而不是 SwiftUI 圆角玻璃形状。
        panel.hasShadow = Self.usesSystemWindowShadow
    }

    /// 让玻璃覆盖隐藏标题栏占用的安全区，保持原有内容尺寸和圆角。
    static func configureHostingView<Content: View>(_ view: NSHostingView<Content>) {
        view.safeAreaRegions = []
        configureRoundedBackingLayer(view)
    }

    /// 应用 `configureRoundedBackingLayer` 接收的新值，并更新相关面板领域状态。
    static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

/// 主面板的键盘、内侧缩放与原生窗口交互。
@MainActor
final class MainPanelWindow: NSPanel {
    var onDismiss: (() -> Void)?
    private let resolver = PanelKeyCommandResolver()
    private var resizeSession: (edge: MainPanelResizeEdge, frame: NSRect, point: NSPoint)?
    private var pendingResizeFrame: NSRect?
    private var resizeDisplayLink: CADisplayLink?

    var isResizeScheduled: Bool { resizeDisplayLink != nil }

    isolated deinit {
        resizeDisplayLink?.invalidate()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if !handleResizeEvent(event) { super.sendEvent(event) }
    }

    /// 返回是否消费了缩放事件；内容区事件继续交由 AppKit 派发。
    func handleResizeEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            endResize()
            let point = screenPoint(for: event)
            if styleMask.contains(.resizable),
               let edge = MainPanelResizeEdge.hit(
                   at: convertPoint(fromScreen: point),
                   in: NSRect(origin: .zero, size: frame.size)
               ) {
                makeKey()
                resizeSession = (edge, frame, point)
                let target = MainPanelResizeDisplayTarget(window: self)
                let link = displayLink(target: target, selector: #selector(MainPanelResizeDisplayTarget.update(_:)))
                resizeDisplayLink = link
                link.add(to: .main, forMode: .common)
                edge.cursor.set()
                return true
            }
        case .leftMouseDragged:
            if resizeSession != nil {
                queueResize(at: screenPoint(for: event))
                return true
            }
        case .leftMouseUp:
            if resizeSession != nil {
                queueResize(at: screenPoint(for: event))
                applyPendingResize()
                endResize()
                return true
            }
        default:
            break
        }
        return false
    }

    /// CG 事件保留发生时的屏幕坐标，窗口移动后不再从旧的窗口内坐标重新换算。
    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let location = event.cgEvent?.unflippedLocation { return location }
        return event.window == nil ? event.locationInWindow : convertPoint(toScreen: event.locationInWindow)
    }

    private func queueResize(at point: NSPoint) {
        guard let session = resizeSession else { return }
        let delta = NSPoint(x: point.x - session.point.x, y: point.y - session.point.y)
        pendingResizeFrame = session.edge.resizedFrame(from: session.frame, delta: delta, minimum: minSize, maximum: maxSize)
    }

    /// 每个显示刷新周期最多更新一次尺寸，积压事件只保留最新位置。
    func applyPendingResize() {
        guard resizeSession != nil, let targetFrame = pendingResizeFrame else { return }
        pendingResizeFrame = nil
        guard targetFrame != frame else { return }
        setFrame(targetFrame, display: false)
    }

    fileprivate func applyPendingResize(from link: CADisplayLink) {
        guard resizeDisplayLink === link else { return }
        applyPendingResize()
    }

    override func orderOut(_ sender: Any?) {
        endResize()
        super.orderOut(sender)
    }

    override func resignKey() {
        endResize()
        super.resignKey()
    }

    override func close() {
        endResize()
        super.close()
    }

    private func endResize() {
        guard resizeSession != nil else { return }
        resizeSession = nil
        pendingResizeFrame = nil
        resizeDisplayLink?.invalidate()
        resizeDisplayLink = nil
        NSCursor.arrow.set()
        if let contentView { invalidateCursorRects(for: contentView) }
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
    override func keyDown(with event: NSEvent) {
        if resolver.command(forKeyCode: event.keyCode) == .dismiss {
            endResize()
            onDismiss?()
            return
        }

        super.keyDown(with: event)
    }

    /// 判断 `cancelOperation` 所描述的面板领域条件是否成立。
    override func cancelOperation(_ sender: Any?) {
        endResize()
        onDismiss?()
    }
}

/// Display link 持有 target；target 弱引用窗口，避免缩放过程中形成保留环。
@MainActor
private final class MainPanelResizeDisplayTarget: NSObject {
    weak var window: MainPanelWindow?

    init(window: MainPanelWindow) {
        self.window = window
    }

    @objc func update(_ link: CADisplayLink) {
        guard let window else {
            link.invalidate()
            return
        }
        window.applyPendingResize(from: link)
    }
}
