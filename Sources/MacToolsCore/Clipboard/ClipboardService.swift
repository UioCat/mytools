// `ClipboardService` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import Foundation

/// 管理 `ClipboardService` 在剪贴板领域中的生命周期、依赖和可变状态。
public final class ClipboardService {
    private let pasteboard: PasteboardClient
    private let classifier: ClipboardClassifier
    private let persist: (ClipboardItem, Data?, AppSettings) throws -> Void
    private var settings: AppSettings
    private var lastChangeCount: Int

    /// 创建 `ClipboardService`，保存传入依赖并建立初始状态。
    public convenience init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings
    ) {
        self.init(
            pasteboard: pasteboard,
            classifier: classifier,
            settings: settings,
            persist: { item, _, currentSettings in
                try repository.upsert(
                    item,
                    historyLimit: currentSettings.clipboard.maxHistoryCount
                )
            }
        )
    }

    /// 创建 `ClipboardService`，保存传入依赖并建立初始状态。
    public convenience init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        repository: ClipboardRepository,
        settings: AppSettings,
        payloadStore: PayloadStore
    ) {
        self.init(
            pasteboard: pasteboard,
            classifier: classifier,
            settings: settings,
            persist: { item, imageData, currentSettings in
                if let imageData {
                    try repository.upsertPNG(
                        item,
                        data: imageData,
                        historyLimit: currentSettings.clipboard.maxHistoryCount
                    )
                } else {
                    try repository.upsert(
                        item,
                        historyLimit: currentSettings.clipboard.maxHistoryCount
                    )
                }
            }
        )
    }

    /// 创建 `ClipboardService`，保存传入依赖并建立初始状态。
    convenience init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        settings: AppSettings,
        upsert: @escaping (ClipboardItem) throws -> Void,
        cacheImageData: @escaping (Data, AppSettings) throws -> String? = { _, _ in nil }
    ) {
        self.init(
            pasteboard: pasteboard,
            classifier: classifier,
            settings: settings,
            persist: { item, imageData, settings in
                var persistedItem = item
                if let imageData {
                    persistedItem.cachedFilePath = try cacheImageData(imageData, settings)
                }
                try upsert(persistedItem)
            }
        )
    }

    /// 创建 `ClipboardService`，保存传入依赖并建立初始状态。
    init(
        pasteboard: PasteboardClient,
        classifier: ClipboardClassifier,
        settings: AppSettings,
        persist: @escaping (ClipboardItem, Data?, AppSettings) throws -> Void
    ) {
        self.pasteboard = pasteboard
        self.classifier = classifier
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
        self.persist = persist
    }

    /// 应用 `updateSettings` 接收的新值，并更新相关剪贴板领域状态。
    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    /// 安排或刷新 `pollOnce` 对应的剪贴板领域工作。
    @discardableResult
    public func pollOnce(sourceApp: String?) throws -> Bool {
        let currentChangeCount = pasteboard.changeCount

        guard settings.clipboard.isRecordingEnabled else {
            lastChangeCount = currentChangeCount
            return false
        }

        guard currentChangeCount != lastChangeCount else {
            return false
        }

        let payload = pasteboard.readPayload()
        let item = classifier.classify(payload: payload, sourceApp: sourceApp)
        guard item.kind != .unknown else {
            lastChangeCount = currentChangeCount
            return false
        }

        let imageData = item.kind == .imageData ? payload.imageData : nil
        try persist(item, imageData, settings)
        lastChangeCount = currentChangeCount
        return true
    }
}
