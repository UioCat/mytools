// 翻译工作台的输入、结果和错误展示模型。
// 将运行时翻译状态转换为可渲染内容，不发起网络请求。

import Foundation

/// 描述 `TranslationWorkspaceState` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum TranslationWorkspaceState: Equatable {
    case idle
    case translating
    case translated(String)
    case failed(String)
}

/// 封装 `TranslationWorkspaceContent` 在 SwiftUI 展示层中的值语义和相关操作。
public struct TranslationWorkspaceContent: Equatable {
    public var settings: TranslationSettings
    public var state: TranslationWorkspaceState

    /// 创建 `TranslationWorkspaceContent`，保存传入依赖并建立初始状态。
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

    /// 为非空原文创建朗读请求，并根据原文自动选择语音语言。
    public func originalSpeechRequest(
        text: String,
        source: TranslationSpeechSource = .translationWorkspace
    ) -> TranslationSpeechRequest? {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }

        return TranslationSpeechRequest(
            text: normalizedText,
            languageCode: TranslationSpeechLanguagePolicy.originalLanguageCode(for: normalizedText),
            source: source
        )
    }

    /// 仅在存在可复制译文时创建朗读请求，并按原文翻译方向选择译文语言。
    public func translatedSpeechRequest(
        originalText: String,
        source: TranslationSpeechSource = .translationWorkspace
    ) -> TranslationSpeechRequest? {
        guard let outputText = copyableOutputText else {
            return nil
        }

        let normalizedOutput = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationSpeechRequest(
            text: normalizedOutput,
            languageCode: TranslationSpeechLanguagePolicy.translatedLanguageCode(forOriginalText: originalText),
            source: source
        )
    }

    /// 返回当前译文的兼容朗读请求。
    public func speechRequest(
        originalText: String,
        source: TranslationSpeechSource = .translationWorkspace
    ) -> TranslationSpeechRequest? {
        translatedSpeechRequest(originalText: originalText, source: source)
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

    /// 仅在提供方已配置、当前未翻译且输入非空时允许提交。
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

/// 描述 `TranslationInputPlaceholderPolicy` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum TranslationInputPlaceholderPolicy {
    /// 判断 `isPlaceholderVisible` 所描述的 SwiftUI 展示层条件是否成立。
    public static func isPlaceholderVisible(inputText: String, isComposingText: Bool) -> Bool {
        inputText.isEmpty && !isComposingText
    }
}
