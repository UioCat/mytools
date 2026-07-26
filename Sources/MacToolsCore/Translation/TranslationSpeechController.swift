// `TranslationSpeechController` 的翻译领域实现。
// 负责翻译请求、提供方和语音播放状态，不管理窗口展示。

import Combine
import Foundation

/// 描述 `TranslationSpeechSource` 在翻译领域中可取的状态、选项或错误。
public enum TranslationSpeechSource: Equatable {
    case translationWorkspace
    case superRightClick
}

/// 封装 `TranslationSpeechRequest` 在翻译领域中的值语义和相关操作。
public struct TranslationSpeechRequest: Equatable {
    public var text: String
    public var languageCode: String
    public var source: TranslationSpeechSource

    /// 创建 `TranslationSpeechRequest`，保存传入依赖并建立初始状态。
    public init(text: String, languageCode: String, source: TranslationSpeechSource) {
        self.text = text
        self.languageCode = languageCode
        self.source = source
    }
}

/// 描述 `TranslationSpeechState` 在翻译领域中可取的状态、选项或错误。
public enum TranslationSpeechState: Equatable {
    case idle
    case speaking(TranslationSpeechRequest)

    public var activeRequest: TranslationSpeechRequest? {
        guard case .speaking(let request) = self else {
            return nil
        }

        return request
    }

    /// 判断 `isSpeaking` 所描述的翻译领域条件是否成立。
    public func isSpeaking(_ request: TranslationSpeechRequest) -> Bool {
        activeRequest == request
    }
}

/// 描述 `TranslationSpeechLanguagePolicy` 在翻译领域中可取的状态、选项或错误。
public enum TranslationSpeechLanguagePolicy {
    /// 计算并返回 `originalLanguageCode` 对应的翻译领域数据或状态结果。
    public static func originalLanguageCode(for text: String) -> String {
        switch TranslationLanguageRouter.targetLanguage(for: text) {
        case "en":
            return "zh-CN"
        default:
            return "en-US"
        }
    }

    /// 计算并返回 `translatedLanguageCode` 对应的翻译领域数据或状态结果。
    public static func translatedLanguageCode(forOriginalText text: String) -> String {
        switch TranslationLanguageRouter.targetLanguage(for: text) {
        case "en":
            return "en-US"
        default:
            return "zh-CN"
        }
    }

    /// 计算并返回 `languageCode` 对应的翻译领域数据或状态结果。
    public static func languageCode(forOriginalText text: String) -> String {
        translatedLanguageCode(forOriginalText: text)
    }

    /// 计算并返回 `displayName` 对应的翻译领域数据或状态结果。
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

/// 为翻译领域中的相关类型提供 `TranslationSpeechCompletion` 别名。
public typealias TranslationSpeechCompletion = @MainActor () -> Void

/// 定义 `TranslationSpeechEngine` 在翻译领域中需要满足的能力边界。
@MainActor
public protocol TranslationSpeechEngine: AnyObject {
    /// 控制 `speak` 对应的语音或交互状态。
    func speak(
        _ request: TranslationSpeechRequest,
        completion: @escaping TranslationSpeechCompletion
    )
    /// 结束 `stop` 对应的翻译领域流程，并释放或重置相关资源。
    func stop()
}

/// 管理翻译朗读状态，并使用播放 generation 忽略旧语音的延迟完成回调。
@MainActor
public final class TranslationSpeechController: ObservableObject {
    @Published public private(set) var state: TranslationSpeechState = .idle

    private let engine: any TranslationSpeechEngine
    private var playbackGeneration = 0

    /// 创建 `TranslationSpeechController`，保存传入依赖并建立初始状态。
    public init(engine: any TranslationSpeechEngine) {
        self.engine = engine
    }

    /// 切换指定朗读请求；相同请求停止，不同请求替换当前播放。
    public func toggle(_ request: TranslationSpeechRequest) {
        if state.isSpeaking(request) {
            stop()
            return
        }

        // 先推进代际再停止引擎，避免旧 utterance 的 completion 把新请求重置为空闲。
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

    /// 停止当前朗读并使已登记的完成回调全部失效。
    public func stop() {
        playbackGeneration &+= 1
        engine.stop()
        state = .idle
    }

    /// 仅当当前朗读来自指定入口时停止，避免一个面板关闭时打断另一个入口。
    public func stop(ifSource source: TranslationSpeechSource) {
        guard state.activeRequest?.source == source else {
            return
        }

        stop()
    }
}
