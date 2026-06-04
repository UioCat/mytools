import Foundation

public final class ClipboardService {
    private let pasteboard: PasteboardClient
    private let classifier: ClipboardClassifier
    private let upsert: (ClipboardItem) throws -> Void
    private let cacheImageData: (Data) throws -> String?
    private var settings: AppSettings
    private var lastChangeCount: Int

    public init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings,
        fileCache: FileCache? = nil
    ) {
        self.pasteboard = pasteboard
        self.classifier = classifier
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
        self.upsert = { item in
            try repository.upsert(item)
        }
        self.cacheImageData = { data in
            try fileCache?.store(data: data, preferredExtension: "png").fileURL.path
        }
    }

    init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        settings: AppSettings,
        upsert: @escaping (ClipboardItem) throws -> Void,
        cacheImageData: @escaping (Data) throws -> String? = { _ in nil }
    ) {
        self.pasteboard = pasteboard
        self.classifier = classifier
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
        self.upsert = upsert
        self.cacheImageData = cacheImageData
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
        var item = classifier.classify(payload: payload, sourceApp: sourceApp)
        guard item.kind != .unknown else {
            lastChangeCount = currentChangeCount
            return
        }

        if item.kind == .imageData, let imageData = payload.imageData {
            item.cachedFilePath = try cacheImageData(imageData)
        }

        try upsert(item)
        lastChangeCount = currentChangeCount
    }
}
