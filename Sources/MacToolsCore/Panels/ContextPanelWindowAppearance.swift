// `ContextPanelWindowAppearance` 的面板领域实现。
// 负责窗口外观和交互策略，不持久化业务数据。

import AppKit

/// 描述 `ContextPanelWindowAppearance` 在面板领域中可取的状态、选项或错误。
public enum ContextPanelWindowAppearance {
    public static let windowStyleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    public static let windowLevel: NSWindow.Level = .popUpMenu
    public static let windowCollectionBehavior: NSWindow.CollectionBehavior = [
        .transient,
        .ignoresCycle,
        .canJoinAllSpaces,
        .canJoinAllApplications
    ]
    public static let usesSystemWindowShadow = false
    public static let windowCornerRadius: CGFloat = 22

    /// 应用 `configurePresentationPolicy` 接收的新值，并更新相关面板领域状态。
    @MainActor
    public static func configurePresentationPolicy(_ panel: NSPanel) {
        panel.level = windowLevel
        panel.collectionBehavior = windowCollectionBehavior
        panel.hidesOnDeactivate = false
    }

    /// 应用 `configureRoundedBackingLayer` 接收的新值，并更新相关面板领域状态。
    @MainActor
    public static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
