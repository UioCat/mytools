import AppKit

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

    @MainActor
    public static func configurePresentationPolicy(_ panel: NSPanel) {
        panel.level = windowLevel
        panel.collectionBehavior = windowCollectionBehavior
        panel.hidesOnDeactivate = false
    }

    @MainActor
    public static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
