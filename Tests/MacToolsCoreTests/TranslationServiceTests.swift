import XCTest
@testable import MacToolsCore

final class TranslationServiceTests: XCTestCase {
    func testBailianProviderWithoutAPIKeyReturnsProviderNotConfigured() async {
        let provider = BailianTranslationProvider(configuration: nil)
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: nil,
            targetLanguage: "zh"
        )

        let result = await provider.translate(request)

        XCTAssertEqual(result, .failure(.providerNotConfigured))
    }

    func testConfiguredBailianProviderSendsOpenAICompatibleRequest() async throws {
        let httpClient = RecordingTranslationHTTPClient(
            response: .success(Self.bailianResponse(text: "你好"))
        )
        let provider = BailianTranslationProvider(
            configuration: BailianTranslationConfiguration(
                apiKey: "sk-test-key",
                model: "qwen-mt-turbo",
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!
            ),
            httpClient: httpClient
        )
        let request = TranslationRequest(
            text: "hello",
            sourceLanguage: "en",
            targetLanguage: "zh"
        )

        let result = await provider.translate(request)

        XCTAssertEqual(result, .success(TranslationResponse(translatedText: "你好", providerID: "bailian")))
        let sentRequest = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(sentRequest.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(sentRequest.httpMethod, "POST")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-key")
        XCTAssertEqual(sentRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(sentRequest.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "qwen-mt-turbo")

        let messages = try XCTUnwrap(json?["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "hello")

        let translationOptions = try XCTUnwrap(json?["translation_options"] as? [String: String])
        XCTAssertEqual(translationOptions["source_lang"], "English")
        XCTAssertEqual(translationOptions["target_lang"], "Chinese")
    }

    func testBailianProviderOmitsSourceLanguageWhenRequestUsesAutoDetection() async throws {
        let httpClient = RecordingTranslationHTTPClient(
            response: .success(Self.bailianResponse(text: "你好"))
        )
        let provider = BailianTranslationProvider(
            configuration: BailianTranslationConfiguration(
                apiKey: "sk-test-key",
                model: "qwen-mt-turbo",
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!
            ),
            httpClient: httpClient
        )

        _ = await provider.translate(
            TranslationRequest(text: "hello", sourceLanguage: nil, targetLanguage: "zh")
        )

        let sentRequest = try XCTUnwrap(httpClient.requests.first)
        let body = try XCTUnwrap(sentRequest.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let translationOptions = try XCTUnwrap(json?["translation_options"] as? [String: String])
        XCTAssertNil(translationOptions["source_lang"])
        XCTAssertEqual(translationOptions["target_lang"], "Chinese")
    }

    func testBailianProviderMapsProviderErrors() async {
        let httpClient = RecordingTranslationHTTPClient(
            response: .success(
                .init(
                    data: Data(#"{"error":{"message":"invalid api key"}}"#.utf8),
                    statusCode: 401
                )
            )
        )
        let provider = BailianTranslationProvider(
            configuration: BailianTranslationConfiguration(
                apiKey: "sk-test-key",
                model: "qwen-mt-turbo",
                endpointURL: URL(string: "https://example.com/v1/chat/completions")!
            ),
            httpClient: httpClient
        )

        let result = await provider.translate(
            TranslationRequest(text: "hello", sourceLanguage: nil, targetLanguage: "zh")
        )

        XCTAssertEqual(result, .failure(.providerFailure("invalid api key")))
    }

    func testTranslateAutomaticallyTargetsChineseForEnglishInput() async {
        let provider = RecordingTranslationProvider(
            response: .success(TranslationResponse(translatedText: "你好", providerID: "test"))
        )
        let service = TranslationService(provider: provider)

        let result = await service.translateAutomatically("hello")

        XCTAssertEqual(
            provider.requests,
            [TranslationRequest(text: "hello", sourceLanguage: nil, targetLanguage: "zh")]
        )
        XCTAssertEqual(result, .success(TranslationResponse(translatedText: "你好", providerID: "test")))
    }

    func testTranslateAutomaticallyTargetsEnglishForChineseInput() async {
        let provider = RecordingTranslationProvider(
            response: .success(TranslationResponse(translatedText: "hello", providerID: "test"))
        )
        let service = TranslationService(provider: provider)

        let result = await service.translateAutomatically("你好")

        XCTAssertEqual(
            provider.requests,
            [TranslationRequest(text: "你好", sourceLanguage: nil, targetLanguage: "en")]
        )
        XCTAssertEqual(result, .success(TranslationResponse(translatedText: "hello", providerID: "test")))
    }

    func testTranslateAutomaticallyTargetsChineseForOtherLanguageInput() async {
        let provider = RecordingTranslationProvider(
            response: .success(TranslationResponse(translatedText: "你好", providerID: "test"))
        )
        let service = TranslationService(provider: provider)

        let result = await service.translateAutomatically("bonjour")

        XCTAssertEqual(
            provider.requests,
            [TranslationRequest(text: "bonjour", sourceLanguage: nil, targetLanguage: "zh")]
        )
        XCTAssertEqual(result, .success(TranslationResponse(translatedText: "你好", providerID: "test")))
    }

    private static func bailianResponse(text: String) -> TranslationHTTPResponse {
        TranslationHTTPResponse(
            data: Data(
                """
                {
                  "choices": [
                    {
                      "message": {
                        "role": "assistant",
                        "content": "\(text)"
                      }
                    }
                  ]
                }
                """.utf8
            ),
            statusCode: 200
        )
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

private final class RecordingTranslationHTTPClient: TranslationHTTPClient {
    private(set) var requests: [URLRequest] = []
    private let response: Result<TranslationHTTPResponse, Error>

    init(response: Result<TranslationHTTPResponse, Error>) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> TranslationHTTPResponse {
        requests.append(request)
        return try response.get()
    }
}
