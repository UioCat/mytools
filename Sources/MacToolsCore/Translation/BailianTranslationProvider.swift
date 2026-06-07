import Foundation

public struct BailianTranslationConfiguration: Equatable {
    public var apiKey: String
    public var model: String
    public var endpointURL: URL

    public init(apiKey: String, model: String, endpointURL: URL) {
        self.apiKey = apiKey
        self.model = model
        self.endpointURL = endpointURL
    }
}

public struct TranslationHTTPResponse: Equatable {
    public var data: Data
    public var statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol TranslationHTTPClient {
    func send(_ request: URLRequest) async throws -> TranslationHTTPResponse
}

public struct URLSessionTranslationHTTPClient: TranslationHTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> TranslationHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return TranslationHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }
}

public final class BailianTranslationProvider: TranslationProvider {
    public let providerID = "bailian"

    private let configuration: BailianTranslationConfiguration?
    private let httpClient: TranslationHTTPClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        configuration: BailianTranslationConfiguration?,
        httpClient: TranslationHTTPClient = URLSessionTranslationHTTPClient()
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    public func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError> {
        guard let configuration, !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.providerNotConfigured)
        }

        do {
            let urlRequest = try makeURLRequest(configuration: configuration, translationRequest: request)
            let response = try await httpClient.send(urlRequest)
            return decode(response, providerID: providerID)
        } catch let error as TranslationError {
            return .failure(error)
        } catch {
            return .failure(.networkUnavailable)
        }
    }

    private func makeURLRequest(
        configuration: BailianTranslationConfiguration,
        translationRequest: TranslationRequest
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = BailianChatCompletionRequest(
            model: configuration.model,
            messages: [
                .init(role: "user", content: translationRequest.text)
            ],
            translationOptions: .init(
                sourceLang: Self.languageName(for: translationRequest.sourceLanguage),
                targetLang: Self.languageName(for: translationRequest.targetLanguage) ?? translationRequest.targetLanguage
            )
        )
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func decode(
        _ response: TranslationHTTPResponse,
        providerID: String
    ) -> Result<TranslationResponse, TranslationError> {
        guard (200..<300).contains(response.statusCode) else {
            return .failure(.providerFailure(errorMessage(from: response.data) ?? "Bailian API returned HTTP \(response.statusCode)."))
        }

        do {
            let payload = try decoder.decode(BailianChatCompletionResponse.self, from: response.data)
            guard let translatedText = payload.choices.first?.message.content, !translatedText.isEmpty else {
                return .failure(.providerFailure("Bailian API response did not include translated text."))
            }

            return .success(TranslationResponse(translatedText: translatedText, providerID: providerID))
        } catch {
            return .failure(.providerFailure("Bailian API response could not be decoded."))
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let payload = try? decoder.decode(BailianErrorResponse.self, from: data) else {
            return nil
        }

        return payload.error?.message
    }

    private static func languageName(for value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "":
            return nil
        case "zh", "zh-cn", "zh-hans", "chinese", "中文", "简体中文":
            return "Chinese"
        case "en", "english", "英语":
            return "English"
        case "ja", "jp", "japanese", "日语":
            return "Japanese"
        case "ko", "korean", "韩语":
            return "Korean"
        case "fr", "french", "法语":
            return "French"
        case "de", "german", "德语":
            return "German"
        case "es", "spanish", "西班牙语":
            return "Spanish"
        case "ru", "russian", "俄语":
            return "Russian"
        default:
            return trimmed
        }
    }
}

private struct BailianChatCompletionRequest: Encodable {
    var model: String
    var messages: [Message]
    var translationOptions: TranslationOptions

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case translationOptions = "translation_options"
    }

    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct TranslationOptions: Encodable {
        var sourceLang: String?
        var targetLang: String

        enum CodingKeys: String, CodingKey {
            case sourceLang = "source_lang"
            case targetLang = "target_lang"
        }
    }
}

private struct BailianChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String
    }
}

private struct BailianErrorResponse: Decodable {
    var error: ErrorPayload?

    struct ErrorPayload: Decodable {
        var message: String?
    }
}
