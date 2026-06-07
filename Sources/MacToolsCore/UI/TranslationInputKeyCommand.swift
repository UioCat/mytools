import Foundation

public enum TranslationInputKeyCommand: Equatable {
    case submit
    case insertNewline
    case selectAll
    case copy
    case paste
    case cut
}

public enum TranslationInputKeyCommandResolver {
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
