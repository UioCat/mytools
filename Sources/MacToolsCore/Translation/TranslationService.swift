// `TranslationService` 的翻译领域实现。
// 负责翻译请求、提供方和语音播放状态，不管理窗口展示。

import Foundation
import NaturalLanguage

/// 串行管理 `TranslationService` 在翻译领域中的可变状态和异步操作。
public actor TranslationService {
    private let provider: TranslationProvider

    /// 创建 `TranslationService`，保存传入依赖并建立初始状态。
    public init(provider: TranslationProvider) {
        self.provider = provider
    }

    /// 自动判断中文文本并在中英目标语言之间路由翻译请求。
    public func translateAutomatically(_ text: String) async -> Result<TranslationResponse, TranslationError> {
        let request = TranslationRequest(
            text: text,
            sourceLanguage: nil,
            targetLanguage: TranslationLanguageRouter.targetLanguage(for: text)
        )

        return await provider.translate(request)
    }
}

/// 描述 `TranslationLanguageRouter` 在翻译领域中可取的状态、选项或错误。
enum TranslationLanguageRouter {
    /// 计算并返回 `targetLanguage` 对应的翻译领域数据或状态结果。
    static func targetLanguage(for text: String) -> String {
        isLikelyChinese(text) ? "en" : "zh"
    }

    /// 判断 `isLikelyChinese` 所描述的翻译领域条件是否成立。
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

    /// 判断 `containsChineseCharacter` 所描述的翻译领域条件是否成立。
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
