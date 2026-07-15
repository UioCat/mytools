import Foundation
import XCTest

final class TranslationModuleSourceTests: XCTestCase {
    func testTranslationTextViewsUseAdaptiveReadableSystemTextColors() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent("Sources/MacTools/App/RuntimeViews.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("textView.textColor = .labelColor"))
        XCTAssertTrue(source.contains("isPlaceholder ? .secondaryLabelColor : .labelColor"))
        XCTAssertFalse(source.contains("textView.textColor = NSColor.white"))
    }
}
