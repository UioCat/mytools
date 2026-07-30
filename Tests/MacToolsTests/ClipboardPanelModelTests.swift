import AppKit
import Foundation
import XCTest
@testable import MacTools
@testable import MacToolsCore

final class ClipboardPanelModelTests: XCTestCase {
    func testClearNonFavoritesAndLoadKeepsFavoriteRecord() async throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let favorite = ClipboardItem.testItem(text: "favorite", isFavorite: true)
        let ordinary = ClipboardItem.testItem(text: "ordinary")
        try repository.upsert(favorite)
        try repository.upsert(ordinary)
        let worker = ClipboardPanelWorker(repository: repository)

        let items = try await worker.clearNonFavoritesAndLoad(limit: 100)

        XCTAssertEqual(items.map(\.id), [favorite.id])
        XCTAssertEqual(try repository.item(id: favorite.id)?.id, favorite.id)
        XCTAssertNil(try repository.item(id: ordinary.id))
    }

    func testMarkUsedAndLoadReturnsUpdatedUsageSnapshot() async throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let item = ClipboardItem.testItem(text: "used")
        let usedAt = Date(timeIntervalSince1970: 123)
        try repository.upsert(item)
        let worker = ClipboardPanelWorker(repository: repository)

        let items = try await worker.markUsedAndLoad(
            id: item.id,
            at: usedAt,
            limit: 100
        )

        XCTAssertEqual(items.first?.id, item.id)
        XCTAssertEqual(items.first?.useCount, 1)
        XCTAssertEqual(items.first?.lastUsedAt, usedAt)
    }

    @MainActor
    func testOlderRefreshCannotOverwriteNewerRefresh() async throws {
        let old = ClipboardItem.testItem(text: "old")
        let newest = ClipboardItem.testItem(text: "new")
        let worker = ControlledClipboardPanelWorker(
            loadResults: [.suspended([old]), .immediate([newest])]
        )
        let model = ClipboardPanelModel(
            worker: worker,
            pasteActionService: PasteActionService(
                pasteboard: FakeWritablePasteboard(),
                eventSender: FakePasteEventSender()
            ),
            logger: makeTestLogger(),
            historyLimit: { 500 }
        )

        async let first: Void = model.refresh()
        await worker.waitUntilFirstLoadIsSuspended()
        await model.refresh()
        await worker.resumeFirstLoad()
        _ = await first

        XCTAssertEqual(model.items.map(\.id), [newest.id])
    }

    @MainActor
    func testPrepareFailureDoesNotPublishSuccessfulCopySideEffects() async throws {
        let initialItems = [ClipboardItem.testItem(text: "initial")]
        let item = ClipboardItem.testItem(
            kind: .imageData,
            text: nil,
            cachedFilePath: "/tmp/missing-image"
        )
        let worker = PrepareFailureClipboardPanelWorker(initialItems: initialItems)
        let pasteboard = FakeWritablePasteboard()
        var localChangeCount = 0
        let model = ClipboardPanelModel(
            worker: worker,
            pasteActionService: PasteActionService(
                pasteboard: pasteboard,
                eventSender: FakePasteEventSender()
            ),
            logger: makeTestLogger(),
            historyLimit: { 500 },
            onLocalChange: { localChangeCount += 1 }
        )
        await model.refresh()

        do {
            try await model.copy(item)
            XCTFail("expected copy to fail")
        } catch MacToolsTestError.expectedFailure {
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(model.items, initialItems)
        XCTAssertEqual(localChangeCount, 0)
        XCTAssertTrue(pasteboard.operations.isEmpty)
    }

    @MainActor
    func testPasteboardWriteFailureDoesNotMarkItemUsed() async throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let imageURL = try temporaryTIFFImageURL()
        defer {
            try? FileManager.default.removeItem(
                at: imageURL.deletingLastPathComponent()
            )
        }
        let item = ClipboardItem.testItem(
            kind: .imageData,
            text: nil,
            cachedFilePath: imageURL.path
        )
        try repository.upsert(item)
        let pasteboard = FakeWritablePasteboard()
        pasteboard.writeError = MacToolsTestError.expectedFailure
        let model = ClipboardPanelModel(
            worker: ClipboardPanelWorker(repository: repository),
            pasteActionService: PasteActionService(
                pasteboard: pasteboard,
                eventSender: FakePasteEventSender()
            ),
            logger: makeTestLogger(),
            historyLimit: { 500 }
        )

        do {
            try await model.copy(item)
            XCTFail("expected copy to fail")
        } catch MacToolsTestError.expectedFailure {
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let stored = try XCTUnwrap(repository.item(id: item.id))
        XCTAssertEqual(stored.useCount, 0)
        XCTAssertNil(stored.lastUsedAt)
    }
}

private actor ControlledClipboardPanelWorker: ClipboardPanelWorking {
    enum LoadResult: Sendable {
        case suspended([ClipboardItem])
        case immediate([ClipboardItem])
    }

    private var loadResults: [LoadResult]
    private var firstLoadIsSuspended = false
    private var firstLoadContinuation: CheckedContinuation<Void, Never>?

    init(loadResults: [LoadResult]) {
        self.loadResults = loadResults
    }

    func load(limit: Int) async throws -> [ClipboardItem] {
        guard !loadResults.isEmpty else {
            throw MacToolsTestError.unexpectedCall
        }
        switch loadResults.removeFirst() {
        case let .immediate(items):
            return items
        case let .suspended(items):
            firstLoadIsSuspended = true
            await withCheckedContinuation {
                firstLoadContinuation = $0
            }
            return items
        }
    }

    func waitUntilFirstLoadIsSuspended() async {
        while !firstLoadIsSuspended {
            await Task.yield()
        }
    }

    func resumeFirstLoad() {
        firstLoadContinuation?.resume()
        firstLoadContinuation = nil
    }

    func markUsedAndLoad(
        id: UUID,
        at date: Date,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func setFavoriteAndLoad(
        id: UUID,
        isFavorite: Bool,
        historyLimit: Int,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func deleteAndLoad(
        id: UUID,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func clearNonFavoritesAndLoad(
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func prepareContent(
        for item: ClipboardItem
    ) async throws -> PreparedPasteboardContent {
        throw MacToolsTestError.unexpectedCall
    }
}

private actor PrepareFailureClipboardPanelWorker: ClipboardPanelWorking {
    private let initialItems: [ClipboardItem]

    init(initialItems: [ClipboardItem]) {
        self.initialItems = initialItems
    }

    func load(limit: Int) async throws -> [ClipboardItem] {
        initialItems
    }

    func markUsedAndLoad(
        id: UUID,
        at date: Date,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func setFavoriteAndLoad(
        id: UUID,
        isFavorite: Bool,
        historyLimit: Int,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func deleteAndLoad(
        id: UUID,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func clearNonFavoritesAndLoad(
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func prepareContent(
        for item: ClipboardItem
    ) async throws -> PreparedPasteboardContent {
        throw MacToolsTestError.expectedFailure
    }
}

private func temporaryTIFFImageURL() throws -> URL {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(x: 0, y: 0, width: 1, height: 1).fill()
    image.unlockFocus()
    guard let data = image.tiffRepresentation else {
        throw MacToolsTestError.expectedFailure
    }

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "ClipboardPanelModelTests-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    let fileURL = root.appendingPathComponent("image.tiff")
    try data.write(to: fileURL)
    return fileURL
}
