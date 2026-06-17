import Foundation

public struct SuperRightClickResult: Equatable {
    public var item: ClipboardItem
    public var translation: Result<TranslationResponse, TranslationError>?
    public var isTranslationPending: Bool

    public init(
        item: ClipboardItem,
        translation: Result<TranslationResponse, TranslationError>?,
        isTranslationPending: Bool = false
    ) {
        self.item = item
        self.translation = translation
        self.isTranslationPending = isTranslationPending
    }
}

public final class SuperRightClickService {
    private let settings: SuperRightClickSettings
    private let selectionCapture: SelectionCapturing
    private let classifier: ClipboardClassifier
    private let translationService: TranslationService

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

    public func handleDecision(_ decision: RightClickDecision, sourceApp: String?) async -> SuperRightClickResult? {
        guard settings.isEnabled, decision == .triggerSuperRightClick else {
            return nil
        }

        let payload = selectionCapture.captureSelection()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)
        let shouldTranslate = item.kind == .text
            && item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return SuperRightClickResult(
            item: item,
            translation: nil,
            isTranslationPending: shouldTranslate
        )
    }

    public func translateText(_ text: String) async -> Result<TranslationResponse, TranslationError> {
        await translationService.translateAutomatically(text)
    }
}
