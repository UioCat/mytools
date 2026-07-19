import Combine
import Foundation

public enum TranslationSpeechSource: Equatable {
    case translationWorkspace
    case superRightClick
}

public struct TranslationSpeechRequest: Equatable {
    public var text: String
    public var languageCode: String
    public var source: TranslationSpeechSource

    public init(text: String, languageCode: String, source: TranslationSpeechSource) {
        self.text = text
        self.languageCode = languageCode
        self.source = source
    }
}

public enum TranslationSpeechState: Equatable {
    case idle
    case speaking(TranslationSpeechRequest)

    public var activeRequest: TranslationSpeechRequest? {
        guard case .speaking(let request) = self else {
            return nil
        }

        return request
    }

    public func isSpeaking(_ request: TranslationSpeechRequest) -> Bool {
        activeRequest == request
    }
}

public enum TranslationSpeechLanguagePolicy {
    public static func originalLanguageCode(for text: String) -> String {
        switch TranslationLanguageRouter.targetLanguage(for: text) {
        case "en":
            return "zh-CN"
        default:
            return "en-US"
        }
    }

    public static func translatedLanguageCode(forOriginalText text: String) -> String {
        switch TranslationLanguageRouter.targetLanguage(for: text) {
        case "en":
            return "en-US"
        default:
            return "zh-CN"
        }
    }

    public static func languageCode(forOriginalText text: String) -> String {
        translatedLanguageCode(forOriginalText: text)
    }

    public static func displayName(for languageCode: String) -> String {
        if languageCode.lowercased().hasPrefix("en") {
            return "英语"
        }
        if languageCode.lowercased().hasPrefix("zh") {
            return "中文"
        }
        return "译文"
    }
}

public typealias TranslationSpeechCompletion = @MainActor () -> Void

@MainActor
public protocol TranslationSpeechEngine: AnyObject {
    func speak(
        _ request: TranslationSpeechRequest,
        completion: @escaping TranslationSpeechCompletion
    )
    func stop()
}

@MainActor
public final class TranslationSpeechController: ObservableObject {
    @Published public private(set) var state: TranslationSpeechState = .idle

    private let engine: any TranslationSpeechEngine
    private var playbackGeneration = 0

    public init(engine: any TranslationSpeechEngine) {
        self.engine = engine
    }

    public func toggle(_ request: TranslationSpeechRequest) {
        if state.isSpeaking(request) {
            stop()
            return
        }

        playbackGeneration &+= 1
        let generation = playbackGeneration
        engine.stop()
        state = .speaking(request)
        engine.speak(request) { [weak self] in
            guard let self, self.playbackGeneration == generation else {
                return
            }

            self.state = .idle
        }
    }

    public func stop() {
        playbackGeneration &+= 1
        engine.stop()
        state = .idle
    }

    public func stop(ifSource source: TranslationSpeechSource) {
        guard state.activeRequest?.source == source else {
            return
        }

        stop()
    }
}
