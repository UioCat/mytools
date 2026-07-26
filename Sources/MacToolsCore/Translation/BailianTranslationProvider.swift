// `BailianTranslationProvider` 的翻译领域实现。
// 负责翻译请求、提供方和语音播放状态，不管理窗口展示。

import Foundation

/// 封装 `BailianTranslationConfiguration` 在翻译领域中的值语义和相关操作。
public struct BailianTranslationConfiguration: Equatable, Sendable {
    public var apiKey: String
    public var model: String
    public var endpointURL: URL

    /// 创建 `BailianTranslationConfiguration`，保存传入依赖并建立初始状态。
    public init(apiKey: String, model: String, endpointURL: URL) {
        self.apiKey = apiKey
        self.model = model
        self.endpointURL = endpointURL
    }
}

/// 封装 `TranslationHTTPResponse` 在翻译领域中的值语义和相关操作。
public struct TranslationHTTPResponse: Equatable, Sendable {
    public var data: Data
    public var statusCode: Int

    /// 创建 `TranslationHTTPResponse`，保存传入依赖并建立初始状态。
    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

/// 定义 `TranslationHTTPClient` 在翻译领域中需要满足的能力边界。
public protocol TranslationHTTPClient: Sendable {
    /// 异步执行 `send` 对应的翻译领域输入输出操作。
    func send(_ request: URLRequest) async throws -> TranslationHTTPResponse
}

/// 封装 `URLSessionTranslationHTTPClient` 在翻译领域中的值语义和相关操作。
public struct URLSessionTranslationHTTPClient: TranslationHTTPClient {
    /// 创建 `URLSessionTranslationHTTPClient`，保存传入依赖并建立初始状态。
    public init() {}

    /// 异步执行 `send` 对应的翻译领域输入输出操作。
    public func send(_ request: URLRequest) async throws -> TranslationHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        return TranslationHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }
}

/// 管理 `BailianTranslationProvider` 在翻译领域中的生命周期、依赖和可变状态。
public final class BailianTranslationProvider: TranslationProvider, Sendable {
    public let providerID = "bailian"

    private let configuration: BailianTranslationConfiguration?
    private let httpClient: TranslationHTTPClient

    /// 创建 `BailianTranslationProvider`，保存传入依赖并建立初始状态。
    public init(
        configuration: BailianTranslationConfiguration?,
        httpClient: TranslationHTTPClient = URLSessionTranslationHTTPClient()
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    /// 调用百炼兼容接口并将 HTTP 响应解码为统一翻译结果。
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

    /// 构造并返回 `makeURLRequest` 所描述的翻译领域对象。
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
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// 转换 `decode` 接收的翻译领域数据，并返回规范化结果。
    private func decode(
        _ response: TranslationHTTPResponse,
        providerID: String
    ) -> Result<TranslationResponse, TranslationError> {
        guard (200..<300).contains(response.statusCode) else {
            return .failure(.providerFailure(errorMessage(from: response.data) ?? "Bailian API returned HTTP \(response.statusCode)."))
        }

        do {
            let payload = try JSONDecoder().decode(BailianChatCompletionResponse.self, from: response.data)
            guard let translatedText = payload.choices.first?.message.content, !translatedText.isEmpty else {
                return .failure(.providerFailure("Bailian API response did not include translated text."))
            }

            return .success(TranslationResponse(translatedText: translatedText, providerID: providerID))
        } catch {
            return .failure(.providerFailure("Bailian API response could not be decoded."))
        }
    }

    /// 计算并返回 `errorMessage` 对应的翻译领域数据或状态结果。
    private func errorMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(BailianErrorResponse.self, from: data) else {
            return nil
        }

        return payload.error?.message
    }

    /// 计算并返回 `languageName` 对应的翻译领域数据或状态结果。
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

/// 封装 `BailianChatCompletionRequest` 在翻译领域中的值语义和相关操作。
private struct BailianChatCompletionRequest: Encodable {
    var model: String
    var messages: [Message]
    var translationOptions: TranslationOptions

    /// 描述 `CodingKeys` 在翻译领域中可取的状态、选项或错误。
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case translationOptions = "translation_options"
    }

    /// 封装 `Message` 在翻译领域中的值语义和相关操作。
    struct Message: Encodable {
        var role: String
        var content: String
    }

    /// 封装 `TranslationOptions` 在翻译领域中的值语义和相关操作。
    struct TranslationOptions: Encodable {
        var sourceLang: String?
        var targetLang: String

        /// 描述 `CodingKeys` 在翻译领域中可取的状态、选项或错误。
        enum CodingKeys: String, CodingKey {
            case sourceLang = "source_lang"
            case targetLang = "target_lang"
        }
    }
}

/// 封装 `BailianChatCompletionResponse` 在翻译领域中的值语义和相关操作。
private struct BailianChatCompletionResponse: Decodable {
    var choices: [Choice]

    /// 封装 `Choice` 在翻译领域中的值语义和相关操作。
    struct Choice: Decodable {
        var message: Message
    }

    /// 封装 `Message` 在翻译领域中的值语义和相关操作。
    struct Message: Decodable {
        var content: String
    }
}

/// 封装 `BailianErrorResponse` 在翻译领域中的值语义和相关操作。
private struct BailianErrorResponse: Decodable {
    var error: ErrorPayload?

    /// 封装 `ErrorPayload` 在翻译领域中的值语义和相关操作。
    struct ErrorPayload: Decodable {
        var message: String?
    }
}
