// `ScreenCaptureSession` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

/// 描述 `ScreenCaptureSessionState` 在截图录屏核心领域中可取的状态、选项或错误。
public enum ScreenCaptureSessionState: Equatable {
    case idle
    case selecting
    case selectionReady(ScreenCaptureSelection)
    case capturingScreenshot
    case editingScreenshot
    case recording(ScreenCaptureSelection)
    case finished
    case cancelled
    case failed

    /// 启动 `beginSelection` 对应的截图录屏核心领域流程，并建立所需资源。
    public mutating func beginSelection() {
        self = .selecting
    }

    /// 更新 `acceptSelection` 对应的交互状态，并保持当前选择或展示约束。
    @discardableResult
    public mutating func acceptSelection(_ selection: ScreenCaptureSelection) -> Bool {
        guard case .selecting = self, selection.isValid else {
            return false
        }

        self = .selectionReady(selection)
        return true
    }

    /// 启动 `beginScreenshot` 对应的截图录屏核心领域流程，并建立所需资源。
    @discardableResult
    public mutating func beginScreenshot() -> Bool {
        guard case .selectionReady = self else {
            return false
        }

        self = .capturingScreenshot
        return true
    }

    /// 启动 `beginEditingScreenshot` 对应的截图录屏核心领域流程，并建立所需资源。
    @discardableResult
    public mutating func beginEditingScreenshot() -> Bool {
        guard case .capturingScreenshot = self else {
            return false
        }

        self = .editingScreenshot
        return true
    }

    /// 启动 `beginRecording` 对应的截图录屏核心领域流程，并建立所需资源。
    @discardableResult
    public mutating func beginRecording() -> Bool {
        guard case let .selectionReady(selection) = self else {
            return false
        }

        self = .recording(selection)
        return true
    }

    /// 结束 `finish` 对应的截图录屏核心领域流程，并释放或重置相关资源。
    public mutating func finish() {
        self = .finished
    }

    /// 计算并返回 `fail` 对应的截图录屏核心领域数据或状态结果。
    public mutating func fail() {
        self = .failed
    }

    /// 判断 `cancel` 所描述的截图录屏核心领域条件是否成立。
    public mutating func cancel() {
        self = .cancelled
    }
}
