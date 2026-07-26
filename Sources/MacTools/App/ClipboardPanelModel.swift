// `ClipboardPanelModel` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import Foundation
import MacToolsCore

/// 管理 `ClipboardPanelModel` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var presentationToken = 0

    private let repository: ClipboardRepository
    private let pasteActionService: PasteActionService
    private let logger: Logger
    private let historyLimit: () -> Int
    private let pageSize: Int
    private let onLocalChange: () -> Void

    /// 创建 `ClipboardPanelModel`，保存传入依赖并建立初始状态。
    init(
        repository: ClipboardRepository,
        pasteActionService: PasteActionService,
        logger: Logger,
        historyLimit: @escaping () -> Int,
        pageSize: Int = 1_000,
        onLocalChange: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.pasteActionService = pasteActionService
        self.logger = logger
        self.historyLimit = historyLimit
        self.pageSize = pageSize
        self.onLocalChange = onLocalChange
    }

    /// 安排或刷新 `refresh` 对应的应用运行时与 AppKit 集成工作。
    func refresh() {
        do {
            items = try repository.search("", limit: pageSize)
        } catch {
            logger.error("clipboard refresh failed: \(error)")
        }
    }

    /// 安排或刷新 `prepareForPresentation` 对应的应用运行时与 AppKit 集成工作。
    func prepareForPresentation() {
        refresh()
        presentationToken += 1
    }

    /// 执行 `perform` 指定的应用运行时与 AppKit 集成动作，并返回执行结果。
    func perform(_ action: ClipboardSelectionAction, on item: ClipboardItem) {
        do {
            switch action {
            case .copy:
                try pasteActionService.copy(item)
            case .copyAndPaste:
                try pasteActionService.copyAndPaste(item)
            }

            try repository.markUsed(id: item.id, at: Date())
            onLocalChange()
            refresh()
        } catch {
            logger.error("clipboard selection failed: \(error)")
        }
    }

    /// 执行 `copy` 对应的应用运行时与 AppKit 集成输入输出操作。
    func copy(_ item: ClipboardItem) throws {
        try pasteActionService.copy(item)
        try repository.markUsed(id: item.id, at: Date())
        onLocalChange()
        refresh()
    }

    /// 执行 `paste` 对应的应用运行时与 AppKit 集成输入输出操作。
    func paste() {
        pasteActionService.paste()
    }

    /// 控制 `toggleFavorite` 对应的语音或交互状态。
    func toggleFavorite(_ item: ClipboardItem) {
        do {
            try repository.setFavorite(
                id: item.id,
                isFavorite: !item.isFavorite,
                historyLimit: historyLimit()
            )
            onLocalChange()
            refresh()
        } catch {
            logger.error("favorite toggle failed: \(error)")
        }
    }

    /// 移除 `delete` 指定的应用运行时与 AppKit 集成数据，并维护关联状态。
    func delete(_ item: ClipboardItem) {
        do {
            try repository.delete(id: item.id)
            onLocalChange()
            refresh()
        } catch {
            logger.error("clipboard delete failed: \(error)")
        }
    }

    /// 移除 `clearNonFavorites` 指定的应用运行时与 AppKit 集成数据，并维护关联状态。
    func clearNonFavorites() {
        do {
            try repository.deleteAllNonFavorites()
            onLocalChange()
            refresh()
        } catch {
            logger.error("clipboard clear failed: \(error)")
        }
    }
}
