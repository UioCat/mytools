import AppKit

public enum ContextPanelWindowAppearance {
    public static let windowStyleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    public static let usesSystemWindowShadow = false
    public static let windowCornerRadius: CGFloat = 22

    public static func configureRoundedBackingLayer(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = windowCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}
