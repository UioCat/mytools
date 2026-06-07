import CoreGraphics

public enum PanelOutsideClickPolicy {
    public static func shouldDismiss(
        panelFrame: CGRect,
        eventScreenLocation: CGPoint
    ) -> Bool {
        !panelFrame.contains(eventScreenLocation)
    }
}
