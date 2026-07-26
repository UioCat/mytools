// `ScreenCaptureMode` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

/// 描述 `ScreenCaptureMode` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenCaptureMode: Equatable, Sendable {
    case screenshot
    case recording

    public static let `default`: ScreenCaptureMode = .screenshot
}
