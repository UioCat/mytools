// 基于 AVSpeechSynthesizer 的系统朗读适配器。
// 负责语音生命周期和完成回调，不决定朗读内容或语言策略。

import AVFAudio
import MacToolsCore

/// 管理 `SystemTranslationSpeechEngine` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class SystemTranslationSpeechEngine: NSObject, TranslationSpeechEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private var completions: [ObjectIdentifier: TranslationSpeechCompletion] = [:]

    /// 创建 `SystemTranslationSpeechEngine`，保存传入依赖并建立初始状态。
    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 控制 `speak` 对应的语音或交互状态。
    func speak(
        _ request: TranslationSpeechRequest,
        completion: @escaping TranslationSpeechCompletion
    ) {
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = AVSpeechSynthesisVoice(language: request.languageCode)
        completions[ObjectIdentifier(utterance)] = completion
        synthesizer.speak(utterance)
    }

    /// 结束 `stop` 对应的应用运行时与 AppKit 集成流程，并释放或重置相关资源。
    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else {
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 结束 `finishPlayback` 对应的应用运行时与 AppKit 集成流程，并释放或重置相关资源。
    private func finishPlayback(for utteranceID: ObjectIdentifier) {
        completions.removeValue(forKey: utteranceID)?()
    }
}

/// 扩展 `SystemTranslationSpeechEngine`，补充本文件所需的应用运行时与 AppKit 集成能力。
extension SystemTranslationSpeechEngine: AVSpeechSynthesizerDelegate {
    /// 响应 `speechSynthesizer` 对应的系统或界面回调，并同步当前交互状态。
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finishPlaybackOnMainActor(for: utterance)
    }

    /// 响应 `speechSynthesizer` 对应的系统或界面回调，并同步当前交互状态。
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finishPlaybackOnMainActor(for: utterance)
    }

    /// 结束 `finishPlaybackOnMainActor` 对应的应用运行时与 AppKit 集成流程，并释放或重置相关资源。
    nonisolated private func finishPlaybackOnMainActor(for utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishPlayback(for: utteranceID)
        }
    }
}
