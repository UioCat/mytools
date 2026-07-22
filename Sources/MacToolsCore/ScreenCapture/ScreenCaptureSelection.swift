import CoreGraphics

public struct ScreenCaptureSelection: Equatable, Sendable {
    public static let minimumSideLength: CGFloat = 8

    public let displayID: UInt32
    public let displayFrame: CGRect
    public let rawSelectionFrame: CGRect

    public init(displayID: UInt32, displayFrame: CGRect, rawSelectionFrame: CGRect) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.rawSelectionFrame = rawSelectionFrame
    }

    public var frame: CGRect {
        rawSelectionFrame.standardized.intersection(displayFrame).integral
    }

    public var isValid: Bool {
        frame.width >= Self.minimumSideLength && frame.height >= Self.minimumSideLength
    }

    public var displayRelativeFrame: CGRect {
        frame.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    public var screenCaptureKitSourceFrame: CGRect {
        let appKitFrame = displayRelativeFrame
        return CGRect(
            x: appKitFrame.minX,
            y: displayFrame.height - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}
