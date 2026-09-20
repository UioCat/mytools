import XCTest
@testable import MacToolsCore

final class SelectionCaptureCancellationTests: XCTestCase {
    func testCancellationWhileAccessibilityIsBlockedPreventsCopyFallback() async {
        let started = expectation(description: "AX read started")
        let reader = SuspendedSelectionReader { started.fulfill() }
        let sender = CancellationPasteSender()
        let pasteboard = CancellationPasteboard()
        let capture = SelectionCaptureService(pasteboard: pasteboard, eventSender: sender, selectedTextReader: reader)
        let task = Task.detached { capture.captureSelection() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        reader.release.signal()
        let result = await task.value
        XCTAssertEqual(sender.copyCount, 0)
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertEqual(result, ClipboardPayload())
    }
}

private final class SuspendedSelectionReader: SelectedTextReading {
    let release = DispatchSemaphore(value: 0)
    let started: () -> Void
    init(started: @escaping () -> Void) { self.started = started }
    func readSelectedText() -> String? {
        started()
        _ = release.wait(timeout: .now() + 3)
        return nil
    }
}

private final class CancellationPasteSender: PasteEventSender {
    var copyCount = 0
    func sendCopyShortcut() { copyCount += 1 }
    func sendPasteShortcut() { XCTFail("Unexpected paste") }
}

private final class CancellationPasteboard: PasteboardClient {
    var changeCount = 0
    var readCount = 0
    func readPayload() -> ClipboardPayload { readCount += 1; return ClipboardPayload() }
}
