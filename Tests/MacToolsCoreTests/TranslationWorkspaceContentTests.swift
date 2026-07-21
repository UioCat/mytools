import XCTest
@testable import MacToolsCore

final class TranslationWorkspaceContentTests: XCTestCase {
    func testConfiguredWorkspaceAllowsManualTextTranslation() {
        let content = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .idle
        )

        XCTAssertEqual(content.inputTitle, "输入文本")
        XCTAssertEqual(content.helperText, "输入中文会翻译成英文，输入英文或其他语言会翻译成中文。")
        XCTAssertEqual(content.inputPlaceholder, "输入中文、英文或其他语言")
        XCTAssertEqual(content.translateButtonTitle, "翻译")
        XCTAssertTrue(content.canSubmit(inputText: "hello"))
    }

    func testWorkspaceBlocksSubmitWhenUnconfiguredOrBlank() {
        let unconfigured = TranslationWorkspaceContent(settings: .init(), state: .idle)
        let configured = TranslationWorkspaceContent(settings: TranslationSettings(apiKey: "sk-test"), state: .idle)

        XCTAssertFalse(unconfigured.canSubmit(inputText: "hello"))
        XCTAssertFalse(configured.canSubmit(inputText: "   "))
    }

    func testInputPlaceholderHidesWhileIMECompositionIsActive() {
        XCTAssertTrue(
            TranslationInputPlaceholderPolicy.isPlaceholderVisible(
                inputText: "",
                isComposingText: false
            )
        )
        XCTAssertFalse(
            TranslationInputPlaceholderPolicy.isPlaceholderVisible(
                inputText: "",
                isComposingText: true
            )
        )
        XCTAssertFalse(
            TranslationInputPlaceholderPolicy.isPlaceholderVisible(
                inputText: "b",
                isComposingText: false
            )
        )
    }

    func testWorkspaceDisplaysTranslationResultAndErrors() {
        let translated = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .translated("你好")
        )
        let failed = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .failed("invalid api key")
        )

        XCTAssertEqual(translated.outputTitle, "译文")
        XCTAssertEqual(translated.outputText, "你好")
        XCTAssertEqual(failed.outputTitle, "错误")
        XCTAssertEqual(failed.outputText, "invalid api key")
    }

    func testWorkspaceExposesCopyableTranslatedOutputOnly() {
        let translated = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .translated("hello")
        )
        let idle = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .idle
        )
        let failed = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .failed("invalid api key")
        )

        XCTAssertEqual(translated.outputCopyButtonTitle, "复制译文")
        XCTAssertEqual(translated.copyableOutputText, "hello")
        XCTAssertNil(idle.copyableOutputText)
        XCTAssertNil(failed.copyableOutputText)
    }

    func testWorkspaceExposesOriginalAndTranslatedSpeechRequests() {
        let translated = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .translated(" Hello ")
        )
        let idle = TranslationWorkspaceContent(
            settings: TranslationSettings(apiKey: "sk-test"),
            state: .idle
        )

        XCTAssertEqual(
            translated.originalSpeechRequest(text: " 你好 "),
            TranslationSpeechRequest(
                text: "你好",
                languageCode: "zh-CN",
                source: .translationWorkspace
            )
        )
        XCTAssertEqual(
            translated.translatedSpeechRequest(originalText: "你好"),
            TranslationSpeechRequest(
                text: "Hello",
                languageCode: "en-US",
                source: .translationWorkspace
            )
        )
        XCTAssertNil(translated.originalSpeechRequest(text: "   "))
        XCTAssertNil(idle.translatedSpeechRequest(originalText: "hello"))
    }
}
