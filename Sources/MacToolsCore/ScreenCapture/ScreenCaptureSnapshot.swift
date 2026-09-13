import CoreGraphics

/// 单次选区会话的屏幕像素，仅在内存中保留，预览和成品共用同一帧。
public struct ScreenCaptureSnapshot {
    public let displayID: UInt32
    public let displayFrame: CGRect
    public let image: CGImage

    public init(displayID: UInt32, displayFrame: CGRect, image: CGImage) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.image = image
    }

    /// 按实际像素比例裁剪，拒绝显示器拓扑变化后的选区。
    public func croppedImage(for selection: ScreenCaptureSelection) -> CGImage? {
        guard selection.isValid, selection.displayID == displayID,
              selection.displayFrame == displayFrame,
              displayFrame.width > 0, displayFrame.height > 0 else {
            return nil
        }
        let source = selection.screenCaptureKitSourceFrame
        let scaleX = CGFloat(image.width) / displayFrame.width
        let scaleY = CGFloat(image.height) / displayFrame.height
        return image.cropping(to: CGRect(
            x: source.minX * scaleX, y: source.minY * scaleY,
            width: source.width * scaleX, height: source.height * scaleY
        ).integral)
    }
}
