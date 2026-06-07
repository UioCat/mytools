import XCTest
@testable import MacToolsCore

final class RightClickStateMachineTests: XCTestCase {
    func testShortPressAllowsSystemMenuAndClearsPressState() {
        var machine = RightClickStateMachine(thresholdMilliseconds: 600)

        XCTAssertEqual(machine.handle(.pressed(atMilliseconds: 1_000)), .none)
        XCTAssertEqual(machine.handle(.released(atMilliseconds: 1_200)), .allowSystemMenu)
        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 1_600)), .none)
    }

    func testLongPressTriggersSuperRightClickAtThreshold() {
        var machine = RightClickStateMachine(thresholdMilliseconds: 600)

        XCTAssertEqual(machine.handle(.pressed(atMilliseconds: 1_000)), .none)

        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 1_599)), .none)
        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 1_600)), .triggerSuperRightClick)
    }

    func testReleaseAfterTriggerClearsPressStateWithoutSystemMenu() {
        var machine = RightClickStateMachine(thresholdMilliseconds: 600)

        XCTAssertEqual(machine.handle(.pressed(atMilliseconds: 1_000)), .none)
        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 1_600)), .triggerSuperRightClick)

        XCTAssertEqual(machine.handle(.released(atMilliseconds: 1_700)), .none)
        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 2_000)), .none)
    }

    func testRepeatedTimerAfterTriggerReturnsNone() {
        var machine = RightClickStateMachine(thresholdMilliseconds: 600)

        XCTAssertEqual(machine.handle(.pressed(atMilliseconds: 1_000)), .none)
        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 1_600)), .triggerSuperRightClick)

        XCTAssertEqual(machine.handle(.timerFired(atMilliseconds: 1_800)), .none)
    }
}

final class SelectionCaptureServiceTests: XCTestCase {
    func testCaptureSelectionUsesAccessibleSelectedTextWithoutCopyShortcut() {
        let pasteboard = FakePasteboardClient(payload: ClipboardPayload(text: "clipboard text"))
        let sender = FakePasteEventSender()
        let reader = FakeSelectedTextReader(selectedText: "selected text")
        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            eventSender: sender,
            selectedTextReader: reader
        )

        let payload = service.captureSelection()

        XCTAssertEqual(payload, ClipboardPayload(text: "selected text"))
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(sender.sendCopyCount, 0)
        XCTAssertEqual(pasteboard.readCount, 0)
    }

    func testCaptureSelectionSendsCopyShortcutThenReadsPayload() {
        let pasteboard = FakePasteboardClient(payload: ClipboardPayload(text: "selected text"))
        let sender = FakePasteEventSender {
            pasteboard.changeCount += 1
        }
        let reader = FakeSelectedTextReader(selectedText: nil)
        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            eventSender: sender,
            selectedTextReader: reader
        )

        let payload = service.captureSelection()

        XCTAssertEqual(payload, ClipboardPayload(text: "selected text"))
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(sender.sendCopyCount, 1)
        XCTAssertEqual(sender.sendPasteCount, 0)
        XCTAssertEqual(pasteboard.readCount, 1)
    }

    func testCaptureSelectionReturnsEmptyPayloadWhenCopyFallbackDoesNotChangePasteboard() {
        let pasteboard = FakePasteboardClient(payload: ClipboardPayload(imageData: Data([1, 2, 3])))
        let sender = FakePasteEventSender()
        let reader = FakeSelectedTextReader(selectedText: nil)
        let service = SelectionCaptureService(
            pasteboard: pasteboard,
            eventSender: sender,
            selectedTextReader: reader
        )

        let payload = service.captureSelection()

        XCTAssertEqual(payload, ClipboardPayload())
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(sender.sendCopyCount, 1)
        XCTAssertEqual(pasteboard.readCount, 0)
    }
}

private final class FakeSelectedTextReader: SelectedTextReading {
    private(set) var readCount = 0
    private let selectedText: String?

    init(selectedText: String?) {
        self.selectedText = selectedText
    }

    func readSelectedText() -> String? {
        readCount += 1
        return selectedText
    }
}

final class SuperRightClickServiceTests: XCTestCase {
    func testHandleDecisionReturnsNilForNonTriggerWithoutCapturingSelection() async {
        let selectionCapture = FakeSelectionCapture(payload: ClipboardPayload(text: "hello"))
        let translationProvider = RecordingTranslationProvider()
        let service = SuperRightClickService(
            settings: SuperRightClickSettings(isEnabled: true, longPressMilliseconds: 600),
            selectionCapture: selectionCapture,
            classifier: ClipboardClassifier(),
            translationService: TranslationService(provider: translationProvider)
        )

        let result = await service.handleDecision(.allowSystemMenu, sourceApp: "Notes")

        XCTAssertNil(result)
        XCTAssertEqual(selectionCapture.captureCount, 0)
        XCTAssertTrue(translationProvider.requests.isEmpty)
    }

    func testHandleDecisionCapturesAndTranslatesTextSelection() async {
        let selectionCapture = FakeSelectionCapture(payload: ClipboardPayload(text: "hello"))
        let translationProvider = RecordingTranslationProvider()
        let service = SuperRightClickService(
            settings: SuperRightClickSettings(isEnabled: true, longPressMilliseconds: 600),
            selectionCapture: selectionCapture,
            classifier: ClipboardClassifier(),
            translationService: TranslationService(provider: translationProvider)
        )

        let result = await service.handleDecision(.triggerSuperRightClick, sourceApp: "Notes")

        XCTAssertEqual(result?.item.kind, .text)
        XCTAssertEqual(result?.item.text, "hello")
        XCTAssertEqual(result?.item.sourceApp, "Notes")
        XCTAssertEqual(
            result?.translation,
            .success(TranslationResponse(translatedText: "translated", providerID: "test"))
        )
        XCTAssertEqual(selectionCapture.captureCount, 1)
        XCTAssertEqual(
            translationProvider.requests,
            [TranslationRequest(text: "hello", sourceLanguage: nil, targetLanguage: "zh")]
        )
    }

    func testHandleDecisionRoutesChineseTextSelectionToEnglishTranslation() async {
        let selectionCapture = FakeSelectionCapture(payload: ClipboardPayload(text: "你好"))
        let translationProvider = RecordingTranslationProvider()
        let service = SuperRightClickService(
            settings: SuperRightClickSettings(isEnabled: true, longPressMilliseconds: 600),
            selectionCapture: selectionCapture,
            classifier: ClipboardClassifier(),
            translationService: TranslationService(provider: translationProvider)
        )

        _ = await service.handleDecision(.triggerSuperRightClick, sourceApp: "Notes")

        XCTAssertEqual(
            translationProvider.requests,
            [TranslationRequest(text: "你好", sourceLanguage: nil, targetLanguage: "en")]
        )
    }

    func testHandleDecisionReturnsNilWhenSuperRightClickIsDisabled() async {
        let selectionCapture = FakeSelectionCapture(payload: ClipboardPayload(text: "hello"))
        let translationProvider = RecordingTranslationProvider()
        let service = SuperRightClickService(
            settings: SuperRightClickSettings(isEnabled: false, longPressMilliseconds: 600),
            selectionCapture: selectionCapture,
            classifier: ClipboardClassifier(),
            translationService: TranslationService(provider: translationProvider)
        )

        let result = await service.handleDecision(.triggerSuperRightClick, sourceApp: "Notes")

        XCTAssertNil(result)
        XCTAssertEqual(selectionCapture.captureCount, 0)
        XCTAssertTrue(translationProvider.requests.isEmpty)
    }
}

private final class FakePasteboardClient: PasteboardClient {
    var changeCount = 0
    private(set) var readCount = 0
    private let payload: ClipboardPayload

    init(payload: ClipboardPayload) {
        self.payload = payload
    }

    func readPayload() -> ClipboardPayload {
        readCount += 1
        return payload
    }
}

private final class FakePasteEventSender: PasteEventSender {
    private(set) var sendCopyCount = 0
    private(set) var sendPasteCount = 0
    private let onCopy: () -> Void

    init(onCopy: @escaping () -> Void = {}) {
        self.onCopy = onCopy
    }

    func sendCopyShortcut() {
        sendCopyCount += 1
        onCopy()
    }

    func sendPasteShortcut() {
        sendPasteCount += 1
    }
}

private final class FakeSelectionCapture: SelectionCapturing {
    private(set) var captureCount = 0
    private let payload: ClipboardPayload

    init(payload: ClipboardPayload) {
        self.payload = payload
    }

    func captureSelection() -> ClipboardPayload {
        captureCount += 1
        return payload
    }
}

private final class RecordingTranslationProvider: TranslationProvider {
    let providerID = "test"
    private(set) var requests: [TranslationRequest] = []

    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        requests.append(request)
        return .success(TranslationResponse(translatedText: "translated", providerID: providerID))
    }
}
