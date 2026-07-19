import XCTest
@testable import MacToolsCore

@MainActor
final class TranslationSpeechControllerTests: XCTestCase {
    func testToggleStartsAndStopsTheSameRequest() {
        let engine = FakeTranslationSpeechEngine()
        let controller = TranslationSpeechController(engine: engine)
        let request = TranslationSpeechRequest(
            text: "Hello",
            languageCode: "en-US",
            source: .translationWorkspace
        )

        controller.toggle(request)

        XCTAssertEqual(controller.state, .speaking(request))
        XCTAssertEqual(engine.spokenRequests, [request])
        XCTAssertEqual(engine.stopCallCount, 1)

        controller.toggle(request)

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(engine.spokenRequests, [request])
        XCTAssertEqual(engine.stopCallCount, 2)
    }

    func testStartingAnotherRequestIgnoresTheStaleCompletion() {
        let engine = FakeTranslationSpeechEngine()
        let controller = TranslationSpeechController(engine: engine)
        let workspaceRequest = TranslationSpeechRequest(
            text: "Hello",
            languageCode: "en-US",
            source: .translationWorkspace
        )
        let superPanelRequest = TranslationSpeechRequest(
            text: "你好",
            languageCode: "zh-CN",
            source: .superRightClick
        )

        controller.toggle(workspaceRequest)
        controller.toggle(superPanelRequest)
        engine.completeRequest(at: 0)

        XCTAssertEqual(controller.state, .speaking(superPanelRequest))

        engine.completeRequest(at: 1)

        XCTAssertEqual(controller.state, .idle)
    }

    func testStopForSourceLeavesOtherPlaybackRunning() {
        let engine = FakeTranslationSpeechEngine()
        let controller = TranslationSpeechController(engine: engine)
        let request = TranslationSpeechRequest(
            text: "你好",
            languageCode: "zh-CN",
            source: .superRightClick
        )

        controller.toggle(request)
        controller.stop(ifSource: .translationWorkspace)

        XCTAssertEqual(controller.state, .speaking(request))

        controller.stop(ifSource: .superRightClick)

        XCTAssertEqual(controller.state, .idle)
    }

    func testSpeechLanguageMatchesAutomaticTranslationDirection() {
        XCTAssertEqual(
            TranslationSpeechLanguagePolicy.languageCode(forOriginalText: "你好，世界"),
            "en-US"
        )
        XCTAssertEqual(
            TranslationSpeechLanguagePolicy.languageCode(forOriginalText: "Hello, world"),
            "zh-CN"
        )
        XCTAssertEqual(TranslationSpeechLanguagePolicy.displayName(for: "en-US"), "英语")
        XCTAssertEqual(TranslationSpeechLanguagePolicy.displayName(for: "zh-CN"), "中文")
    }
}

@MainActor
private final class FakeTranslationSpeechEngine: TranslationSpeechEngine {
    private(set) var spokenRequests: [TranslationSpeechRequest] = []
    private(set) var stopCallCount = 0
    private var completions: [TranslationSpeechCompletion] = []

    func speak(
        _ request: TranslationSpeechRequest,
        completion: @escaping TranslationSpeechCompletion
    ) {
        spokenRequests.append(request)
        completions.append(completion)
    }

    func stop() {
        stopCallCount += 1
    }

    func completeRequest(at index: Int) {
        completions[index]()
    }
}
