import AppKit
import MacToolsCore

/// 会话协调器通过展示边界交接状态，原生窗口仍由各平台控制器拥有。
@MainActor
protocol ScreenSelectionPresenting: AnyObject {
    func prepareForCapture(onCancel: @escaping () -> Void)
    func present(
        snapshots: [ScreenCaptureSnapshot],
        onSelection: @escaping (ScreenCaptureSelection, ScreenCaptureMode) -> Void,
        onCancel: @escaping () -> Void
    )
    func presentEditor(
        _ editorView: NSView,
        for selection: ScreenCaptureSelection,
        escapeHandler: @escaping (Bool) -> ScreenshotEditorEscapeAction
    ) -> Bool
    func dismiss()
}

@MainActor
protocol ScreenshotEditing: AnyObject {
    func prepare(
        image: CGImage,
        selection: ScreenCaptureSelection,
        settings: ScreenCaptureSettings,
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    )
    func preparedContentView() -> NSView?
    func handleEscape(hasMarkedText: Bool) -> ScreenshotEditorEscapeAction
    func dismiss()
}

@MainActor
protocol RecordingControlPresenting: AnyObject {
    func show(selection: ScreenCaptureSelection, onStop: @escaping () -> Void)
    func hide()
}

extension ScreenSelectionOverlayController: ScreenSelectionPresenting {}
extension ScreenshotEditorPanelController: ScreenshotEditing {}
extension RecordingControlPanelController: RecordingControlPresenting {}
