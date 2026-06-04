import Foundation

public final class ClipboardService {
    private let pasteboard: PasteboardClient
    private let classifier: ClipboardClassifier
    private let repository: ClipboardRepository
    private var settings: AppSettings
    private var lastChangeCount: Int

    public init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings
    ) {
        self.pasteboard = pasteboard
        self.classifier = classifier
        self.repository = repository
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    public func pollOnce(sourceApp: String?) throws {
        let currentChangeCount = pasteboard.changeCount

        guard settings.clipboard.isRecordingEnabled else {
            lastChangeCount = currentChangeCount
            return
        }

        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount

        let payload = pasteboard.readPayload()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)
        guard item.kind != .unknown else {
            return
        }

        try repository.upsert(item)
    }
}
