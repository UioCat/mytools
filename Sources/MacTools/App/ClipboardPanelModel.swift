import Foundation
import MacToolsCore

@MainActor
final class ClipboardPanelModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let repository: ClipboardRepository
    private let pasteActionService: PasteActionService
    private let logger: Logger
    private let limit: () -> Int

    init(
        repository: ClipboardRepository,
        pasteActionService: PasteActionService,
        logger: Logger,
        limit: @escaping () -> Int
    ) {
        self.repository = repository
        self.pasteActionService = pasteActionService
        self.logger = logger
        self.limit = limit
    }

    func refresh() {
        do {
            items = try repository.search("", limit: limit())
        } catch {
            logger.error("clipboard refresh failed: \(error)")
        }
    }

    func perform(_ action: ClipboardSelectionAction, on item: ClipboardItem) {
        do {
            switch action {
            case .copy:
                try pasteActionService.copy(item)
            case .copyAndPaste:
                try pasteActionService.copyAndPaste(item)
            }

            try repository.markUsed(id: item.id, at: Date())
            refresh()
        } catch {
            logger.error("clipboard selection failed: \(error)")
        }
    }
}
