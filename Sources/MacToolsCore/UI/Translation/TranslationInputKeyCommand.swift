// 翻译输入框的键盘命令解析规则。
// 将按键与修饰键转换为提交或换行意图，不直接处理 AppKit 事件。

import Foundation

/// 描述 `TranslationInputKeyCommand` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum TranslationInputKeyCommand: Equatable {
    case submit
    case insertNewline
    case selectAll
    case copy
    case paste
    case cut
}

/// 描述 `TranslationInputKeyCommandResolver` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum TranslationInputKeyCommandResolver {
    /// 构建并返回 `command` 对应的 SwiftUI 界面内容或展示状态。
    public static func command(
        forKeyCode keyCode: UInt16,
        isShiftPressed: Bool
    ) -> TranslationInputKeyCommand? {
        command(
            forKeyCode: keyCode,
            charactersIgnoringModifiers: nil,
            isCommandPressed: false,
            isShiftPressed: isShiftPressed
        )
    }

    /// 构建并返回 `command` 对应的 SwiftUI 界面内容或展示状态。
    public static func command(
        forKeyCode keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        isCommandPressed: Bool,
        isShiftPressed: Bool
    ) -> TranslationInputKeyCommand? {
        if isCommandPressed {
            if let command = editingCommand(
                forKeyCode: keyCode,
                charactersIgnoringModifiers: charactersIgnoringModifiers
            ) {
                return command
            }
        }

        guard keyCode == 36 || keyCode == 76 else {
            return nil
        }

        return isShiftPressed ? .insertNewline : .submit
    }

    /// 构建并返回 `editingCommand` 对应的 SwiftUI 界面内容或展示状态。
    private static func editingCommand(
        forKeyCode keyCode: UInt16,
        charactersIgnoringModifiers: String?
    ) -> TranslationInputKeyCommand? {
        switch charactersIgnoringModifiers?.lowercased() {
        case "a":
            return .selectAll
        case "c":
            return .copy
        case "v":
            return .paste
        case "x":
            return .cut
        default:
            break
        }

        switch keyCode {
        case 0:
            return .selectAll
        case 8:
            return .copy
        case 9:
            return .paste
        case 7:
            return .cut
        default:
            return nil
        }
    }
}
