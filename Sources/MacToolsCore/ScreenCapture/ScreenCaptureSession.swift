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

    public mutating func beginSelection() {
        self = .selecting
    }

    @discardableResult
    public mutating func acceptSelection(_ selection: ScreenCaptureSelection) -> Bool {
        guard selection.isValid else {
            return false
        }

        self = .selectionReady(selection)
        return true
    }

    @discardableResult
    public mutating func beginScreenshot() -> Bool {
        guard case .selectionReady = self else {
            return false
        }

        self = .capturingScreenshot
        return true
    }

    @discardableResult
    public mutating func beginEditingScreenshot() -> Bool {
        guard case .capturingScreenshot = self else {
            return false
        }

        self = .editingScreenshot
        return true
    }

    @discardableResult
    public mutating func beginRecording() -> Bool {
        guard case let .selectionReady(selection) = self else {
            return false
        }

        self = .recording(selection)
        return true
    }

    public mutating func finish() {
        self = .finished
    }

    public mutating func fail() {
        self = .failed
    }

    public mutating func cancel() {
        self = .cancelled
    }
}
