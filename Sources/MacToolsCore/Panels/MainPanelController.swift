// `MainPanelController` 的面板领域实现。
// 负责窗口外观和交互策略，不持久化业务数据。

import AppKit
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
    public static let windowStyleMask: NSWindow.StyleMask = [.borderless, .resizable]
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
            // NSWindow 阴影跟随矩形窗口边界，而不是 SwiftUI 圆角玻璃形状。
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

    /// 应用 `configureRoundedBackingLayer` 接收的新值，并更新相关面板领域状态。
    static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

/// 管理 `EscapeDismissPanel` 在面板领域中的生命周期、依赖和可变状态。
@MainActor
private final class EscapeDismissPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private let resolver = PanelKeyCommandResolver()

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
    override func keyDown(with event: NSEvent) {
        if resolver.command(forKeyCode: event.keyCode) == .dismiss {
            onDismiss?()
            return
        }

        super.keyDown(with: event)
    }

    /// 判断 `cancelOperation` 所描述的面板领域条件是否成立。
    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }
}
