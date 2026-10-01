import Foundation
import XCTest
@testable import MacToolsCore

final class TranslationHTTPFailureTests: XCTestCase {
    private let request = TranslationRequest(text: "synthetic input", sourceLanguage: nil, targetLanguage: "zh")
    private let configuration = BailianTranslationConfiguration(
        apiKey: "synthetic-placeholder", model: "qwen-mt-flash", endpointURL: URL(string: "https://example.invalid/translation")!)

    func testHTTPAndInvalidPayloadMatrix() async {
        let cases: [(Int, String, TranslationError)] = [
            (401, #"{"error":{"message":"synthetic provider rejection"}}"#, .providerFailure("synthetic provider rejection")),
            (503, "<html>synthetic unavailable</html>", .providerFailure("Bailian API returned HTTP 503.")),
            (429, "{bad JSON", .providerFailure("Bailian API returned HTTP 429.")),
            (200, #"{"choices":[]}"#, .providerFailure("Bailian API response did not include translated text.")),
            (200, #"{"choices":[{"message":{"content":""}}]}"#, .providerFailure("Bailian API response did not include translated text.")),
            (200, "{bad JSON", .providerFailure("Bailian API response could not be decoded.")),
            (200, #"{"choices":[{"message":{"content":null}}]}"#, .providerFailure("Bailian API response could not be decoded."))
        ]
        for (status, body, expected) in cases {
            let client = TranslationMatrixHTTPClient(result: .success(.init(data: Data(body.utf8), statusCode: status)))
            let provider = BailianTranslationProvider(configuration: configuration, httpClient: client)
            let result = await provider.translate(request)
            XCTAssertEqual(result, .failure(expected), "HTTP \(status), synthetic payload \(body)")
            let count = await client.requestCount
            XCTAssertEqual(count, 1)
        }
    }

    func testNetworkExceptionMatrix() async {
        for code: URLError.Code in [.notConnectedToInternet, .timedOut, .cancelled] {
            let client = TranslationMatrixHTTPClient(result: .failure(URLError(code)))
            let provider = BailianTranslationProvider(configuration: configuration, httpClient: client)
            let result = await provider.translate(request)
            XCTAssertEqual(result, .failure(.networkUnavailable), "Transport exception \(code)")
        }
    }

    func testUnconfiguredRequestsNeverReachHTTPBoundary() async {
        var blank = configuration
        blank.apiKey = " \n"
        for configuration in [nil, blank] {
            let client = TranslationMatrixHTTPClient(result: .failure(URLError(.notConnectedToInternet)))
            let provider = BailianTranslationProvider(configuration: configuration, httpClient: client)
            let result = await provider.translate(request)
            XCTAssertEqual(result, .failure(.providerNotConfigured))
            let count = await client.requestCount
            XCTAssertEqual(count, 0)
        }
    }
}

private actor TranslationMatrixHTTPClient: TranslationHTTPClient {
    let result: Result<TranslationHTTPResponse, Error>
    var requestCount = 0
    init(result: Result<TranslationHTTPResponse, Error>) { self.result = result }
    func send(_ request: URLRequest) async throws -> TranslationHTTPResponse {
        requestCount += 1
        return try result.get()
    }
}
