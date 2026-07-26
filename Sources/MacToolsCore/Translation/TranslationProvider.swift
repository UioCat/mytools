// `TranslationProvider` 的翻译领域实现。
// 负责翻译请求、提供方和语音播放状态，不管理窗口展示。

import Foundation

/// 封装 `TranslationRequest` 在翻译领域中的值语义和相关操作。
public struct TranslationRequest: Equatable, Sendable {
    public var text: String
    public var sourceLanguage: String?
    public var targetLanguage: String

    /// 创建 `TranslationRequest`，保存传入依赖并建立初始状态。
    public init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

/// 封装 `TranslationResponse` 在翻译领域中的值语义和相关操作。
public struct TranslationResponse: Equatable, Sendable {
    public var translatedText: String
    public var providerID: String

    /// 创建 `TranslationResponse`，保存传入依赖并建立初始状态。
    public init(translatedText: String, providerID: String) {
        self.translatedText = translatedText
        self.providerID = providerID
    }
}

/// 描述 `TranslationError` 在翻译领域中可取的状态、选项或错误。
public enum TranslationError: Error, Equatable, Sendable {
    case providerNotConfigured
    case networkUnavailable
    case providerFailure(String)
}

/// 定义 `TranslationProvider` 在翻译领域中需要满足的能力边界。
public protocol TranslationProvider: Sendable {
    var providerID: String { get }

    /// 执行翻译请求，并将提供方错误归一化为领域错误。
    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError>
}
