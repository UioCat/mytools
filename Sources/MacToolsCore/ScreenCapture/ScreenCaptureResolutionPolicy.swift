import CoreGraphics

public enum ScreenCaptureResolutionPolicy {
    public static func outputPixelSize(
        for sourceSize: CGSize,
        pointPixelScale: CGFloat,
        purpose: ScreenCaptureMode
    ) -> CGSize {
        let outputScale: CGFloat = purpose == .screenshot ? max(1, pointPixelScale) : 1
        return CGSize(
            width: max(1, (sourceSize.width * outputScale).rounded()),
            height: max(1, (sourceSize.height * outputScale).rounded())
        )
    }
}
