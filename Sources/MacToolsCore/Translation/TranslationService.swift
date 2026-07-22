import Foundation
import NaturalLanguage

public actor TranslationService {
    private let provider: TranslationProvider

    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    public func translateAutomatically(_ text: String) async -> Result<TranslationResponse, TranslationError> {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: nil,
            targetLanguage: TranslationLanguageRouter.targetLanguage(for: text)
        )

        return await provider.translate(request)
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

enum TranslationLanguageRouter {
    static func targetLanguage(for text: String) -> String {
        isLikelyChinese(text) ? "en" : "zh"
    }

    private static func isLikelyChinese(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        if let dominantLanguage = NLLanguageRecognizer.dominantLanguage(for: trimmedText) {
            return dominantLanguage == .simplifiedChinese || dominantLanguage == .traditionalChinese
        }

        return containsChineseCharacter(in: trimmedText)
    }

    private static func containsChineseCharacter(in text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}
