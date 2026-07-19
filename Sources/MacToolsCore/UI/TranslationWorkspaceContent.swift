import Foundation

public enum TranslationWorkspaceState: Equatable {
    case idle
    case translating
    case translated(String)
    case failed(String)
}

public struct TranslationWorkspaceContent: Equatable {
    public var settings: TranslationSettings
    public var state: TranslationWorkspaceState

    public init(settings: TranslationSettings, state: TranslationWorkspaceState) {
        self.settings = settings
        self.state = state
    }

    public var headerSubtitle: String {
        settings.isConfigured ? "百炼翻译已配置" : "等待百炼 API Key 配置"
    }

    public var helperText: String {
        if settings.isConfigured {
            return "输入中文会翻译成英文，输入英文或其他语言会翻译成中文。"
        }

        return "请先在设置的翻译区域填写 DASHSCOPE_API_KEY。"
    }

    public var inputTitle: String {
        "输入文本"
    }

    public var inputPlaceholder: String {
        "输入中文、英文或其他语言"
    }

    public var outputCopyButtonTitle: String {
        "复制译文"
    }

    public var outputTitle: String {
        switch state {
        case .failed:
            return "错误"
        default:
            return "译文"
        }
    }

    public var outputText: String {
        switch state {
        case .idle:
            return "翻译结果会显示在这里"
        case .translating:
            return "正在翻译..."
        case .translated(let text):
            return text
        case .failed(let message):
            return message
        }
    }

    public var copyableOutputText: String? {
        guard case .translated(let text) = state else {
            return nil
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : text
    }

    public func speechRequest(
        originalText: String,
        source: TranslationSpeechSource = .translationWorkspace
    ) -> TranslationSpeechRequest? {
        guard let outputText = copyableOutputText else {
            return nil
        }

        let normalizedOutput = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationSpeechRequest(
            text: normalizedOutput,
            languageCode: TranslationSpeechLanguagePolicy.languageCode(forOriginalText: originalText),
            source: source
        )
    }

    public var isOutputPlaceholder: Bool {
        switch state {
        case .idle, .translating:
            return true
        case .translated, .failed:
            return false
        }
    }

    public var translateButtonTitle: String {
        state == .translating ? "翻译中" : "翻译"
    }

    public func canSubmit(inputText: String) -> Bool {
        guard settings.isConfigured else {
            return false
        }

        guard state != .translating else {
            return false
        }

        return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum TranslationInputPlaceholderPolicy {
    public static func isPlaceholderVisible(inputText: String, isComposingText: Bool) -> Bool {
        inputText.isEmpty && !isComposingText
    }
}
