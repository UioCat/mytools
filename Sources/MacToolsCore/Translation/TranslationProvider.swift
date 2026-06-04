import Foundation

public struct TranslationRequest: Equatable {
    public let text: String
    public let sourceLanguage: String?
    public let targetLanguage: String

    public init(text: String, sourceLanguage: String?, targetLanguage: String) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}

public struct TranslationResponse: Equatable {
    public let translatedText: String
    public let providerID: String

    public init(translatedText: String, providerID: String) {
        self.translatedText = translatedText
        self.providerID = providerID
    }
}

public enum TranslationError: Error, Equatable {
    case providerNotConfigured
    case networkUnavailable
    case providerFailure(String)
}

public protocol TranslationProvider {
    var providerID: String { get }

    func translate(_ request: TranslationRequest) async -> Result<TranslationResponse, TranslationError>
}
