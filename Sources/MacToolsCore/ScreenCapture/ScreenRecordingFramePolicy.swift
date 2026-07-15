import ScreenCaptureKit

public enum ScreenRecordingFramePolicy {
    public static func shouldAppend(
        frameStatus: SCFrameStatus,
        hasImageBuffer: Bool
    ) -> Bool {
        frameStatus == .complete && hasImageBuffer
    }
}

public enum ScreenRecordingCompletionPolicy {
    public static func isSuccessful(
        writerCompleted: Bool,
        hasRecordedFailure: Bool,
        hasCaptureStopError: Bool
    ) -> Bool {
        writerCompleted && !hasRecordedFailure && !hasCaptureStopError
    }
}
