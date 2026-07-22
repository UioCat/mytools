public enum ScreenCaptureMode: Equatable, Sendable {
    case screenshot
    case recording

    public static let `default`: ScreenCaptureMode = .screenshot
}
