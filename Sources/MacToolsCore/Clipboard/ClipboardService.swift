import Foundation

public final class ClipboardService {
    private let pasteboard: PasteboardClient
    private let classifier: ClipboardClassifier
    private let upsert: (ClipboardItem) throws -> Void
    private let cacheImageData: (Data, AppSettings) throws -> String?
    private var settings: AppSettings
    private var lastChangeCount: Int

    public convenience init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings,
        fileCache: FileCache? = nil
    ) {
        self.init(
            pasteboard: pasteboard,
            classifier: classifier,
            repository: repository,
            settings: settings,
            fileCacheProvider: { _ in fileCache }
        )
    }

    public convenience init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings,
        fileCacheProvider: @escaping (AppSettings) -> FileCache?
    ) {
        self.init(
            pasteboard: pasteboard,
            classifier: classifier,
            settings: settings,
            upsert: { item in
                try repository.upsert(item)
            },
            cacheImageData: { data, settings in
                try fileCacheProvider(settings)?.store(
                    data: data,
                    preferredExtension: "png",
                    maxBytes: ClipboardCacheLimit.bytes(forMegabytes: settings.clipboard.maxCacheMegabytes)
                ).fileURL.path
            }
        )
    }

    init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        settings: AppSettings,
        upsert: @escaping (ClipboardItem) throws -> Void,
        cacheImageData: @escaping (Data, AppSettings) throws -> String? = { _, _ in nil }
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
            item.cachedFilePath = try cacheImageData(imageData, settings)
        }

        try upsert(item)
        lastChangeCount = currentChangeCount
    }
}
