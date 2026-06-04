import Foundation

public final class TranslationService {
    private let provider: TranslationProvider

    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    public func translateToChinese(_ text: String) async -> Result<TranslationResponse, TranslationError> {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: nil,
            targetLanguage: "zh"
        )

        return await provider.translate(request)
    }
}
