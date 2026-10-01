import Combine
import Foundation
import MacToolsCore

/// 持有翻译页请求状态；HTTP 提供方可注入，页面负责朗读与原生文本交互。
@MainActor
final class RuntimeTranslationRequestController: ObservableObject {
    @Published private(set) var state: TranslationWorkspaceState = .idle
    @Published private(set) var translatedOriginalText = ""
    private var requestTask: Task<Void, Never>?
    private var requestGeneration = 0
    private let makeProvider: @Sendable (BailianTranslationConfiguration?) -> any TranslationProvider

    init(makeProvider: @escaping @Sendable (BailianTranslationConfiguration?) -> any TranslationProvider = {
        BailianTranslationProvider(configuration: $0)
    }) {
        self.makeProvider = makeProvider
    }

    @discardableResult
    func submit(_ inputText: String, settings: TranslationSettings) -> Bool {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TranslationWorkspaceContent(settings: settings, state: state).canSubmit(inputText: text) else { return false }
        requestGeneration &+= 1
        let generation = requestGeneration
        state = .translating
        let service = TranslationService(provider: makeProvider(settings.bailianConfiguration))
        requestTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let result = await service.translateAutomatically(text)
            guard !Task.isCancelled, let self, requestGeneration == generation else { return }
            requestTask = nil
            switch result {
            case .success(let response):
                translatedOriginalText = text
                state = .translated(response.translatedText)
            case .failure(let error):
                state = .failed(Self.message(for: error))
            }
        }
        return true
    }

    func cancel() {
        guard requestTask != nil else { return }
        requestGeneration &+= 1
        requestTask?.cancel()
        requestTask = nil
        translatedOriginalText = ""
        state = .idle
    }

    deinit { requestTask?.cancel() }

    private static func message(for error: TranslationError) -> String {
        switch error {
        case .providerNotConfigured:
            return "请先在设置里填写 DASHSCOPE_API_KEY。"
        case .networkUnavailable:
            return "无法连接到百炼服务，请检查网络后重试。"
        case .providerFailure(let message):
            return message
        }
    }
}
