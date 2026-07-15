import CoreGraphics

public enum ScreenCaptureOverlayLayout {
    public static let modeToolbarSize = CGSize(width: 196, height: 44)
    public static let editorToolbarSize = CGSize(width: 720, height: 92)
    public static let recordingControlSize = CGSize(width: 176, height: 48)

    private static let edgeInset: CGFloat = 12
    private static let topInset: CGFloat = 16
    private static let toolbarGap: CGFloat = 12

    public static func modeToolbarFrame(displayBounds: CGRect) -> CGRect {
        CGRect(
            x: displayBounds.midX - modeToolbarSize.width / 2,
            y: displayBounds.maxY - topInset - modeToolbarSize.height,
            width: modeToolbarSize.width,
            height: modeToolbarSize.height
        )
    }

    public static func editorToolbarFrame(
        selectionFrame: CGRect,
        displayBounds: CGRect
    ) -> CGRect {
        let selection = selectionFrame.standardized
        let availableWidth = max(0, displayBounds.width - edgeInset * 2)
        let toolbarSize = CGSize(
            width: min(editorToolbarSize.width, availableWidth),
            height: editorToolbarSize.height
        )
        let minimumX = displayBounds.minX + edgeInset
        let maximumX = displayBounds.maxX - edgeInset - toolbarSize.width
        let preferredX = selection.maxX - toolbarSize.width
        let x = min(max(preferredX, minimumX), maximumX)

        let belowY = selection.minY - toolbarGap - toolbarSize.height
        let aboveY = selection.maxY + toolbarGap
        let preferredY = belowY >= displayBounds.minY + edgeInset ? belowY : aboveY
        let minimumY = displayBounds.minY + edgeInset
        let maximumY = displayBounds.maxY - edgeInset - toolbarSize.height
        let y = min(max(preferredY, minimumY), maximumY)

        return CGRect(origin: CGPoint(x: x, y: y), size: toolbarSize)
    }

    public static func recordingControlFrame(visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - recordingControlSize.width / 2,
            y: visibleFrame.maxY - topInset - recordingControlSize.height,
            width: recordingControlSize.width,
            height: recordingControlSize.height
        )
    }
}
