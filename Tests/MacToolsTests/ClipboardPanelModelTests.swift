import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class ClipboardPanelModelTests: XCTestCase {
    @MainActor
    func testQueryAndPaginationReachOldFavoritesAndKeepGlobalCatalog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardModel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ClipboardRepository(database: try .inMemory())
        let old = item(1, favorite: true, tags: ["Archive"])
        try repository.upsert(old)
        for index in 2...6 { try repository.upsert(item(index)) }
        let model = ClipboardPanelModel(repository: repository,
            pasteActionService: PasteActionService(pasteboard: SilentPasteboard(), eventSender: SilentSender()),
            logger: Logger(debugLogDirectory: directory), historyLimit: { 500 }, pageSize: 2)
        model.prepareForPresentation()
        XCTAssertEqual(model.items.map(\.id), [item(6).id, item(5).id])
        XCTAssertTrue(model.hasMoreItems)
        XCTAssertEqual(model.catalog.favoriteCount, 1)
        model.loadMore()
        XCTAssertEqual(model.items.map(\.id), [item(6).id, item(5).id, item(4).id, item(3).id])
        model.updateQuery(.init(category: .favorites, tag: "archive"))
        XCTAssertEqual(model.items.map(\.id), [old.id])
        XCTAssertFalse(model.hasMoreItems)
        XCTAssertEqual(model.catalog.tags.map(\.name), ["Archive"])
        model.updateQuery(.init(text: "Synthetic 2"))
        XCTAssertEqual(model.items.map(\.id), [item(2).id])
        model.prepareForPresentation()
        XCTAssertEqual(model.items.map(\.id), [item(6).id, item(5).id])
    }

    private func item(_ index: Int, favorite: Bool = false, tags: [String] = []) -> ClipboardItem {
        ClipboardItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!, kind: .text,
            displayTitle: "Synthetic \(index)", searchableText: "Synthetic \(index)", text: "Synthetic \(index)",
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: nil, contentHash: "synthetic-\(index)",
            createdAt: Date(timeIntervalSince1970: Double(index)), lastUsedAt: nil, useCount: 0,
            isPinned: false, isFavorite: favorite, tags: tags)
    }
}
private struct SilentPasteboard: WritablePasteboard {
    func writeText(_ text: String) {}
    func writeFileURL(_ url: URL) {}
    func writeImageData(_ data: Data) throws {}
}
private struct SilentSender: PasteEventSender {
    func sendCopyShortcut() {}
    func sendPasteShortcut() {}
}
