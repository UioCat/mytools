// `SuperRightClickService` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import Foundation

/// 封装 `SuperRightClickResult` 在超级右键领域中的值语义和相关操作。
public struct SuperRightClickResult: Equatable, Sendable {
    public var item: ClipboardItem
    public var sourceApplication: SuperRightClickSourceApplication?
    public var translation: Result<TranslationResponse, TranslationError>?
    public var isTranslationPending: Bool

    /// 创建 `SuperRightClickResult`，保存传入依赖并建立初始状态。
    public init(
        item: ClipboardItem,
        sourceApplication: SuperRightClickSourceApplication? = nil,
        translation: Result<TranslationResponse, TranslationError>?,
        isTranslationPending: Bool = false
    ) {
        self.item = item
        self.sourceApplication = sourceApplication
        self.translation = translation
        self.isTranslationPending = isTranslationPending
    }
}

/// 串行执行超级右键的选区捕获、分类和翻译请求构建。
public actor SuperRightClickService {
    private let settings: SuperRightClickSettings
    private let selectionCapture: SelectionCapturing
    private let classifier: ClipboardClassifier
    private let translationService: TranslationService

    /// 创建 `SuperRightClickService`，保存传入依赖并建立初始状态。
    public init(
        settings: SuperRightClickSettings,
        selectionCapture: SelectionCapturing,
        classifier: ClipboardClassifier,
        translationService: TranslationService
    ) {
        self.settings = settings
        self.selectionCapture = selectionCapture
        self.classifier = classifier
        self.translationService = translationService
    }

    /// 在功能启用且收到长按决策时捕获选区，并标记文本条目需要异步翻译。
    public func handleDecision(
        _ decision: RightClickDecision,
        sourceApplication: SuperRightClickSourceApplication?
    ) async -> SuperRightClickResult? {
        guard settings.isEnabled, decision == .triggerSuperRightClick else {
            return nil
        }

        // 捕获和分类先产出可展示结果，网络翻译由调用方随后执行，避免延迟首屏。
        let payload = selectionCapture.captureSelection()
        let item = classifier.classify(
            payload: payload,
            sourceApp: sourceApplication?.localizedName
        )
        let shouldTranslate = item.kind == .text
            && item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return SuperRightClickResult(
            item: item,
            sourceApplication: sourceApplication,
            translation: nil,
            isTranslationPending: shouldTranslate
        )
    }

    /// 使用统一翻译服务自动判断目标语言并返回结果。
    public func translateText(_ text: String) async -> Result<TranslationResponse, TranslationError> {
        await translationService.translateAutomatically(text)
    }
}
