import XCTest
@testable import MacToolsCore

final class TranslationInputKeyCommandTests: XCTestCase {
    func testReturnSubmitsTranslationInput() {
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(forKeyCode: 36, isShiftPressed: false),
            .submit
        )
    }

    func testShiftReturnInsertsNewline() {
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(forKeyCode: 36, isShiftPressed: true),
            .insertNewline
        )
    }

    func testCommandShortcutsUseCharacterIdentityWhenAvailable() {
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 99,
                charactersIgnoringModifiers: "a",
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .selectAll
        )
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 99,
                charactersIgnoringModifiers: "c",
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .copy
        )
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 99,
                charactersIgnoringModifiers: "v",
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .paste
        )
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 99,
                charactersIgnoringModifiers: "x",
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .cut
        )
    }

    func testCommandShortcutsFallBackToMacVirtualKeyCodes() {
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 0,
                charactersIgnoringModifiers: nil,
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .selectAll
        )
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 8,
                charactersIgnoringModifiers: nil,
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .copy
        )
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 9,
                charactersIgnoringModifiers: nil,
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .paste
        )
        XCTAssertEqual(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 7,
                charactersIgnoringModifiers: nil,
                isCommandPressed: true,
                isShiftPressed: false
            ),
            .cut
        )
    }

    func testNonReturnKeyHasNoInputCommand() {
        XCTAssertNil(
            TranslationInputKeyCommandResolver.command(forKeyCode: 0, isShiftPressed: false)
        )
        XCTAssertNil(
            TranslationInputKeyCommandResolver.command(
                forKeyCode: 0,
                charactersIgnoringModifiers: "a",
                isCommandPressed: false,
                isShiftPressed: false
            )
        )
    }
}
