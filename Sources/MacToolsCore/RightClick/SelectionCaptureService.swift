import Foundation

public protocol SelectionCapturing {
    func captureSelection() -> ClipboardPayload
}

public final class SelectionCaptureService: SelectionCapturing {
    private let pasteboard: PasteboardClient
    private let eventSender: PasteEventSender

    public init(pasteboard: PasteboardClient, eventSender: PasteEventSender) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
    }

    public func captureSelection() -> ClipboardPayload {
        eventSender.sendPasteShortcut()
        Thread.sleep(forTimeInterval: 0.05)
        return pasteboard.readPayload()
    }
}
