import CoreGraphics

public enum ScreenshotAnnotation: Equatable {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)
    case mosaic(CGRect)
}

public struct ScreenshotAnnotationStore: Equatable {
    public private(set) var annotations: [ScreenshotAnnotation] = []

    public init() {}

    public mutating func append(_ annotation: ScreenshotAnnotation) {
        annotations.append(annotation)
    }

    @discardableResult
    public mutating func undo() -> ScreenshotAnnotation? {
        annotations.popLast()
    }
}
