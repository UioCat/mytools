// 剪贴板面板的运行时状态模型。
// 负责查询仓储并响应复制、收藏和删除动作，不直接管理 NSPanel 生命周期。

import Foundation
import MacToolsCore

/// 管理 `ClipboardPanelModel` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var presentationToken = 0

    private let worker: any ClipboardPanelWorking
    private let pasteActionService: PasteActionService
    private let logger: Logger
    private let historyLimit: () -> Int
    private let pageSize: Int
    private let onLocalChange: () -> Void
    private var generation = 0

    /// 创建 `ClipboardPanelModel`，保存传入依赖并建立初始状态。
    init(
        worker: any ClipboardPanelWorking,
        pasteActionService: PasteActionService,
        logger: Logger,
        historyLimit: @escaping () -> Int,
        pageSize: Int = 1_000,
        onLocalChange: @escaping () -> Void = {}
    ) {
        self.worker = worker
        self.pasteActionService = pasteActionService
        self.logger = logger
        self.historyLimit = historyLimit
        self.pageSize = pageSize
        self.onLocalChange = onLocalChange
    }

    /// 安排或刷新 `refresh` 对应的应用运行时与 AppKit 集成工作。
    func refresh() async {
        let generation = nextGeneration()
        do {
            let items = try await worker.load(limit: pageSize)
            apply(items: items, generation: generation)
        } catch {
            logger.error("clipboard refresh failed: \(error)")
        }
    }

    /// 安排或刷新 `prepareForPresentation` 对应的应用运行时与 AppKit 集成工作。
    func prepareForPresentation() {
        presentationToken += 1
        Task {
            await refresh()
        }
    }

    /// 执行 `copy` 对应的应用运行时与 AppKit 集成输入输出操作。
    func copy(
        _ item: ClipboardItem,
        validateBeforeWrite: () throws -> Void = {}
    ) async throws {
        let generation = nextGeneration()
        let content = try await worker.prepareContent(for: item)
        try validateBeforeWrite()
        try pasteActionService.write(content)
        do {
            let items = try await worker.markUsedAndLoad(
                id: item.id,
                at: Date(),
                limit: pageSize
            )
            apply(items: items, generation: generation)
            onLocalChange()
        } catch {
            await refresh()
            throw error
        }
    }

    /// 执行 `paste` 对应的应用运行时与 AppKit 集成输入输出操作。
    func paste() {
        pasteActionService.paste()
    }

    /// 控制 `toggleFavorite` 对应的语音或交互状态。
    func toggleFavorite(_ item: ClipboardItem) async {
        let generation = nextGeneration()
        do {
            let items = try await worker.setFavoriteAndLoad(
                id: item.id,
                isFavorite: !item.isFavorite,
                historyLimit: historyLimit(),
                limit: pageSize
            )
            apply(items: items, generation: generation)
            onLocalChange()
        } catch {
            logger.error("favorite toggle failed: \(error)")
        }
    }

    /// 移除 `delete` 指定的应用运行时与 AppKit 集成数据，并维护关联状态。
    func delete(_ item: ClipboardItem) async {
        let generation = nextGeneration()
        do {
            let items = try await worker.deleteAndLoad(
                id: item.id,
                limit: pageSize
            )
            apply(items: items, generation: generation)
            onLocalChange()
        } catch {
            logger.error("clipboard delete failed: \(error)")
        }
    }

    /// 移除 `clearNonFavorites` 指定的应用运行时与 AppKit 集成数据，并维护关联状态。
    func clearNonFavorites() async {
        let generation = nextGeneration()
        do {
            let items = try await worker.clearNonFavoritesAndLoad(limit: pageSize)
            apply(items: items, generation: generation)
            onLocalChange()
        } catch {
            logger.error("clipboard clear failed: \(error)")
        }
    }

    /// 为一次异步操作分配单调递增的状态发布代次。
    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    /// 仅发布当前最新异步操作返回的快照。
    private func apply(items: [ClipboardItem], generation: Int) {
        guard generation == self.generation else { return }
        self.items = items
    }
}
