import Foundation

public final class ClipboardService {
    private let pasteboard: PasteboardClient
    private let classifier: ClipboardClassifier
    private let upsert: (ClipboardItem) throws -> Void
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
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
        self.upsert = { item in
            try repository.upsert(item)
        }
    }

    init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        settings: AppSettings,
        upsert: @escaping (ClipboardItem) throws -> Void
    ) {
        self.pasteboard = pasteboard
        self.classifier = classifier
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
        self.upsert = upsert
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

        let payload = pasteboard.readPayload()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)
        guard item.kind != .unknown else {
            lastChangeCount = currentChangeCount
            return
        }

        try upsert(item)
        lastChangeCount = currentChangeCount
    }
}
