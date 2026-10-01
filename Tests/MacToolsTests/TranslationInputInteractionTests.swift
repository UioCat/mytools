import AppKit
import XCTest
@testable import MacTools

final class TranslationInputInteractionTests: XCTestCase {
    @MainActor
    func testReturnWhileComposingDoesNotSubmitTranslation() throws {
        let view = TranslationInputTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        var submissions = 0
        view.onSubmit = { submissions += 1 }
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))

        view.keyDown(with: event)

        XCTAssertEqual(submissions, 0, "Return must be available to the native input method while composing")
        view.unmarkText()
        view.keyDown(with: event)
        XCTAssertEqual(submissions, 1, "Normal Return still submits once")
    }
}
