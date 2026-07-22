import Foundation

public struct TranslationRequest: Equatable, Sendable {
    public var text: String
    public var sourceLanguage: String?
    public var targetLanguage: String

    public init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

public struct TranslationResponse: Equatable, Sendable {
    public var translatedText: String
    public var providerID: String

    public init(translatedText: String, providerID: String) {
        self.translatedText = translatedText
        self.providerID = providerID
    }
}

public enum TranslationError: Error, Equatable, Sendable {
    case providerNotConfigured
    case networkUnavailable
    case providerFailure(String)
}

public protocol TranslationProvider: Sendable {
    var providerID: String { get }

    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError>
}
