import XCTest
@testable import MacToolsCore

final class TranslationInputEditorLayoutTests: XCTestCase {
    func testCaretAndPlaceholderShareTheSameOrigin() {
        let layout = TranslationInputEditorLayout.standard

        XCTAssertEqual(layout.placeholderLeadingPadding, layout.textContainerWidthInset)
        XCTAssertEqual(layout.placeholderTopPadding, layout.textContainerHeightInset)
        XCTAssertEqual(layout.lineFragmentPadding, 0)
        XCTAssertEqual(layout.caretLeadingOffset, layout.placeholderLeadingOffset)
    }
}
