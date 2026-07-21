import AVFAudio
import MacToolsCore

@MainActor
final class SystemTranslationSpeechEngine: NSObject, TranslationSpeechEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private var completions: [ObjectIdentifier: TranslationSpeechCompletion] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ request: TranslationSpeechRequest,
        completion: @escaping TranslationSpeechCompletion
    ) {
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = AVSpeechSynthesisVoice(language: request.languageCode)
        completions[ObjectIdentifier(utterance)] = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused else {
            return
        }

        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishPlayback(for utteranceID: ObjectIdentifier) {
        completions.removeValue(forKey: utteranceID)?()
    }
}

extension SystemTranslationSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finishPlaybackOnMainActor(for: utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finishPlaybackOnMainActor(for: utterance)
    }

    nonisolated private func finishPlaybackOnMainActor(for utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            self?.finishPlayback(for: utteranceID)
        }
    }
}
