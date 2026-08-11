// 截图编辑器 AppKit 第一响应者路由，保证输入法与原生文本命令优先消费按键。

import AppKit

public enum ScreenshotEditorKeyEventRoute: Equatable, Sendable {
    case forwardToResponder
    case consumed
    case cancelSession
}

public enum ScreenshotEditorKeyEventRouter {
    @MainActor
    public static func route(
        event: NSEvent,
        firstResponder: NSResponder?,
        handler: (Bool) -> ScreenshotEditorEscapeAction
    ) -> ScreenshotEditorKeyEventRoute {
        let textView = firstResponder as? NSTextView
        if event.keyCode == 53 {
            switch handler(textView?.hasMarkedText() == true) {
            case .forwardToInput:
                return .forwardToResponder
            case .cancelEditing, .deselect:
                return .consumed
            case .cancelSession:
                return .cancelSession
            }
        }

        guard let textView else {
            return .forwardToResponder
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) else {
            return .forwardToResponder
        }
        var permittedModifiers: NSEvent.ModifierFlags = [.command, .capsLock]
        if event.keyCode == 76 {
            permittedModifiers.insert(.numericPad)
        }
        guard modifiers.subtracting(permittedModifiers).isEmpty else {
            return .forwardToResponder
        }
        switch event.keyCode {
        case 6:
            textView.undoManager?.undo()
            return .consumed
        case 36, 76:
            textView.insertNewline(nil)
            return .consumed
        default:
            return .forwardToResponder
        }
    }
}
