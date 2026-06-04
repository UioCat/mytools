import Foundation

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

    public func handleDecision(_ decision: RightClickDecision, sourceApp: String?) async -> ClipboardItem? {
        guard settings.isEnabled, decision == .triggerSuperRightClick else {
            return nil
        }

        let payload = selectionCapture.captureSelection()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)

        if item.kind == .text, let text = item.text {
            _ = await translationService.translateToChinese(text)
        }

        return item
    }
}
