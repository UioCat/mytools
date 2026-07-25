import Foundation
import XCTest

final class TranslationModuleSourceTests: XCTestCase {
    func testTranslationModuleOffersOriginalAndTranslatedSpeechControls() throws {
        let source = try runtimeViewsSource()

        XCTAssertTrue(source.contains("speechButton(for: originalSpeechRequest, textRole: \"原文\")"))
        XCTAssertTrue(source.contains("speechButton(for: translatedSpeechRequest, textRole: \"译文\")"))
        XCTAssertTrue(source.contains("speechController.stop(ifSource: .translationWorkspace)"))
    }

    func testTranslationTextViewsUseAdaptiveReadableSystemTextColors() throws {
        let source = try runtimeViewsSource()

        XCTAssertTrue(source.contains("textView.textColor = .labelColor"))
        XCTAssertTrue(source.contains("isPlaceholder ? .secondaryLabelColor : .labelColor"))
        XCTAssertFalse(source.contains("textView.textColor = NSColor.white"))
    }

    func testCredentialUnavailableStatusDoesNotClaimKeychainIsRuntimeStorage() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/UI/TranslationSettingsEditor.swift"
        )

        XCTAssertTrue(source.contains("翻译凭据暂时不可用"))
        XCTAssertFalse(source.contains("Keychain 凭据不可访问"))
    }

    private func runtimeViewsSource() throws -> String {
        try sourceFile("Sources/MacTools/App/RuntimeViews.swift")
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(path)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
