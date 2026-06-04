import AppKit
import CoreGraphics
import Foundation

public protocol WritablePasteboard {
    func writeText(_ text: String)
    func writeFileURL(_ url: URL)
}

public protocol PasteEventSender {
    func sendCopyShortcut()
    func sendPasteShortcut()
}

public final class PasteActionService {
    private let pasteboard: WritablePasteboard
    private let eventSender: PasteEventSender

    public init(pasteboard: WritablePasteboard, eventSender: PasteEventSender) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
    }

    public func copy(_ item: ClipboardItem) throws {
        if let text = item.text {
            pasteboard.writeText(text)
            return
        }

        if let path = item.originalPath ?? item.cachedFilePath {
            pasteboard.writeFileURL(URL(fileURLWithPath: path))
            return
        }

        throw PasteActionError.unsupportedItem
    }

    public func copyAndPaste(_ item: ClipboardItem) throws {
        try copy(item)
        paste()
    }

    public func paste() {
        eventSender.sendPasteShortcut()
    }
}

public enum PasteActionError: Error, Equatable {
    case unsupportedItem
}

public final class SystemWritablePasteboard: WritablePasteboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func writeText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func writeFileURL(_ url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}

public final class SystemPasteEventSender: PasteEventSender {
    public init() {}

    public func sendCopyShortcut() {
        sendCommandShortcut(virtualKey: 8)
    }

    public func sendPasteShortcut() {
        sendCommandShortcut(virtualKey: 9)
    }

    private func sendCommandShortcut(virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)

        keyDown?.flags = [.maskCommand]
        keyUp?.flags = [.maskCommand]
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
