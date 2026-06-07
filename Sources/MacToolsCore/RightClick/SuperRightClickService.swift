import Foundation

public struct SuperRightClickResult: Equatable {
    public var item: ClipboardItem
    public var translation: Result<TranslationResponse, TranslationError>?

    public init(
        item: ClipboardItem,
        translation: Result<TranslationResponse, TranslationError>?
    ) {
        self.item = item
        self.translation = translation
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
        var translation: Result<TranslationResponse, TranslationError>?

        if item.kind == .text, let text = item.text {
            translation = await translationService.translateAutomatically(text)
        }

        return SuperRightClickResult(item: item, translation: translation)
    }
}
