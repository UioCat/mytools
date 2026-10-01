import AppKit
import XCTest
@testable import MacToolsCore

final class ShortcutCaptureTests: XCTestCase {
    @MainActor
    func testUnsupportedPunctuationDoesNotReplaceExistingShortcut() throws {
        let field = WindowLayoutShortcutCaptureTextField()
        var saved: [HotKeyBinding?] = []
        field.configure(
            shortcut: .init(key: "A", modifiers: ["Option"]),
            placeholder: "",
            onShortcutChange: { saved.append($0); return true }
        )
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .option,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "[", charactersIgnoringModifiers: "[", isARepeat: false, keyCode: 33
        ))

        field.keyDown(with: event)

        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(field.stringValue, "Option+A")
    }
}
