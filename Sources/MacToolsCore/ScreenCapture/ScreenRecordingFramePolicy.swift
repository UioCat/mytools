// `ScreenRecordingFramePolicy` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import ScreenCaptureKit

/// 描述 `ScreenRecordingFramePolicy` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenRecordingFramePolicy {
    /// 判断 `shouldAppend` 所描述的截图录屏核心领域条件是否成立。
    public static func shouldAppend(
        frameStatus: SCFrameStatus,
        hasImageBuffer: Bool
    ) -> Bool {
        frameStatus == .complete && hasImageBuffer
    }
}

/// 描述 `ScreenRecordingCompletionPolicy` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenRecordingCompletionPolicy {
    /// 判断 `isSuccessful` 所描述的截图录屏核心领域条件是否成立。
    public static func isSuccessful(
        writerCompleted: Bool,
        hasRecordedFailure: Bool,
        hasCaptureStopError: Bool
    ) -> Bool {
        writerCompleted && !hasRecordedFailure && !hasCaptureStopError
    }
}
