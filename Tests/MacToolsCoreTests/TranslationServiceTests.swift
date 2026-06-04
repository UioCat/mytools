import XCTest
@testable import MacToolsCore

final class TranslationServiceTests: XCTestCase {
    func testBaiduProviderWithoutConfigurationReturnsProviderNotConfigured() async {
        let provider = BaiduTranslationProvider(configuration: nil)
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: nil,
            targetLanguage: "zh"
        )

        let result = await provider.translate(request)

        XCTAssertEqual(result, .failure(.providerNotConfigured))
    }

    func testConfiguredBaiduProviderReturnsPendingWiringFailure() async {
        let provider = BaiduTranslationProvider(
            configuration: BaiduTranslationConfiguration(appID: "app-id", secret: "secret")
        )
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: "en",
            targetLanguage: "zh"
        )

        let result = await provider.translate(request)

        XCTAssertEqual(
            result,
            .failure(.providerFailure("Baidu API wiring is waiting for supplied credentials and endpoint details."))
        )
    }

    func testTranslateToChineseForwardsRequestToProvider() async {
        let provider = RecordingTranslationProvider(
            response: .success(TranslationResponse(translatedText: "你好", providerID: "test"))
        )
        let service = TranslationService(provider: provider)

        let result = await service.translateToChinese("hello")

        XCTAssertEqual(
            provider.requests,
            [TranslationRequest(text: "hello", sourceLanguage: nil, targetLanguage: "zh")]
        )
        XCTAssertEqual(result, .success(TranslationResponse(translatedText: "你好", providerID: "test")))
    }
}

private final class RecordingTranslationProvider: TranslationProvider {
    let providerID = "test"
    private(set) var requests: [TranslationRequest] = []
    private let response: Result<TranslationResponse, TranslationError>

    init(response: Result<TranslationResponse, TranslationError>) {
        self.response = response
    }

    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        requests.append(request)
        return response
    }
}
