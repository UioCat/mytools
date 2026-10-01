import Foundation
import GRDB
import XCTest
@testable import MacToolsCore

final class ClipboardStorageRegressionTests: XCTestCase {
    func testWholeLibraryFiltersBeforePaginationAndBuildsGlobalCatalog() throws {
        let repository = ClipboardRepository(database: try .inMemory())
        let old = item(1, favorite: true, tags: ["Archive", "École"])
        try repository.upsert(old)
        for index in 2...6 { try repository.upsert(item(index)) }
        XCTAssertEqual(try repository.queryPage(.init(category: .favorites), limit: 2).map(\.id), [old.id])
        XCTAssertEqual(try repository.queryPage(.init(text: "archive", category: .favorites), limit: 2).map(\.id), [old.id])
        XCTAssertEqual(try repository.queryPage(.init(category: .favorites, tag: "e\u{301}cole"), limit: 2).map(\.id), [old.id])
        let catalog = try repository.catalog()
        XCTAssertEqual(catalog.favoriteCount, 1)
        XCTAssertTrue(catalog.hasClearableItems)
        XCTAssertEqual(catalog.tags.map(\.name), ["Archive", "École"])
        let first = try repository.queryPage(.init(), limit: 2)
        let second = try repository.queryPage(.init(), limit: 2, offset: 2)
        XCTAssertEqual(first.map(\.id), [item(6).id, item(5).id])
        XCTAssertEqual(second.map(\.id), [item(4).id, item(3).id])
    }

    func testByteBudgetEvictsOrdinaryAndKeepsProtectedPayloadsOverBudget() throws {
        let directory = temporaryDirectory()
        let payloads = PayloadStore(rootDirectory: directory)
        let repository = ClipboardRepository(database: try .inMemory(), payloadStore: payloads, cacheLimitBytes: Int64(png.count))
        let normal = item(1, kind: .imageData)
        let favorite = item(2, kind: .imageData, favorite: true)
        let pinned = item(3, kind: .imageData, pinned: true)
        try repository.upsertPNG(normal, data: png + Data([1]))
        try repository.upsertPNG(favorite, data: png + Data([2]))
        try repository.upsertPNG(pinned, data: png + Data([3]))
        _ = try repository.enforceCacheLimit()
        XCTAssertNil(try repository.item(id: normal.id))
        XCTAssertNotNil(try repository.item(id: favorite.id))
        XCTAssertNotNil(try repository.item(id: pinned.id))
        XCTAssertEqual(try payloads.objectRelativePaths().count, 2)
    }

    func testByteBudgetCountsOneSharedObjectOnce() throws {
        let payloads = PayloadStore(rootDirectory: temporaryDirectory())
        let repository = ClipboardRepository(database: try .inMemory(), payloadStore: payloads, cacheLimitBytes: Int64(png.count))
        let first = item(1, kind: .imageData)
        let second = item(2, kind: .imageData)
        try repository.upsertPNG(first, data: png)
        try repository.upsertPNG(second, data: png)
        _ = try repository.enforceCacheLimit()
        XCTAssertEqual(try repository.search("", limit: 10).count, 2)
        XCTAssertEqual(try payloads.objectRelativePaths().count, 1)
    }

    func testStoredPNGReferenceBlocksConcurrentReconciliation() throws {
        let payloads = PayloadStore(rootDirectory: temporaryDirectory())
        let repository = ClipboardRepository(database: try .inMemory(), payloadStore: payloads)
        let referenceReady = DispatchSemaphore(value: 0)
        let resumeReference = DispatchSemaphore(value: 0)
        let referenceDone = expectation(description: "reference committed")
        let reconcileStarted = DispatchSemaphore(value: 0)
        let reconcileDone = DispatchSemaphore(value: 0)
        let failures = LockedFailures()
        let image = item(1, kind: .imageData)
        let data = png
        DispatchQueue.global().async {
            defer { referenceDone.fulfill() }
            do {
                try payloads.withStoredPNG(data) { payload in
                    referenceReady.signal()
                    resumeReference.wait()
                    _ = try repository.upsert(image, payload: payload, enqueuesSyncChange: false)
                }
            } catch { failures.append(error) }
        }
        XCTAssertEqual(referenceReady.wait(timeout: .now() + 3), .success)
        DispatchQueue.global().async {
            reconcileStarted.signal()
            do { try repository.reconcilePayloadStorage() } catch { failures.append(error) }
            reconcileDone.signal()
        }
        XCTAssertEqual(reconcileStarted.wait(timeout: .now() + 3), .success)
        // 有界等待仅检查互斥：清理不得在引用事务开始前完成。
        let completedEarly = reconcileDone.wait(timeout: .now() + 0.1) == .success
        XCTAssertFalse(completedEarly)
        resumeReference.signal()
        wait(for: [referenceDone], timeout: 3)
        if !completedEarly { XCTAssertEqual(reconcileDone.wait(timeout: .now() + 3), .success) }
        XCTAssertTrue(failures.isEmpty)
        XCTAssertNotNil(try repository.item(id: image.id)?.payloadID)
        XCTAssertEqual(try payloads.objectRelativePaths().count, 1)
    }

    func testUnprotectingPayloadAppliesBudgetAndConfigurationDoesNoFileIO() throws {
        let directory = temporaryDirectory()
        let payloads = PayloadStore(rootDirectory: directory)
        let repository = ClipboardRepository(database: try .inMemory(), payloadStore: payloads)
        repository.configureCacheLimit(megabytes: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let favorite = item(1, kind: .imageData, favorite: true)
        try repository.upsertPNG(favorite, data: png)
        XCTAssertNotNil(try repository.item(id: favorite.id))
        try repository.setFavorite(id: favorite.id, isFavorite: false)
        XCTAssertNil(try repository.item(id: favorite.id))
        XCTAssertTrue(try payloads.objectRelativePaths().isEmpty)
    }

    func testRollbackDiscardsNewPNGButKeepsExistingSharedObject() throws {
        enum RejectedReference: Error { case rejected }
        let payloads = PayloadStore(rootDirectory: temporaryDirectory())
        XCTAssertThrowsError(try payloads.withStoredPNG(png) { _ in throw RejectedReference.rejected })
        XCTAssertTrue(try payloads.objectRelativePaths().isEmpty)
        let existing = try payloads.storePNG(png)
        XCTAssertThrowsError(try payloads.withStoredPNG(png) { _ in throw RejectedReference.rejected })
        XCTAssertTrue(payloads.contains(relativePath: existing.relativePath))
    }

    private var png: Data { Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")! }
    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StorageRegression-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func item(_ index: Int, kind: ClipboardContentKind = .text, favorite: Bool = false, pinned: Bool = false, tags: [String] = []) -> ClipboardItem {
        ClipboardItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!, kind: kind,
                      displayTitle: "Synthetic \(index)", searchableText: "Synthetic \(index)", text: kind == .text ? "Synthetic \(index)" : nil,
                      originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: nil, contentHash: "synthetic-\(index)",
                      createdAt: Date(timeIntervalSince1970: Double(index)), lastUsedAt: nil, useCount: 0,
                      isPinned: pinned, isFavorite: favorite, tags: tags)
    }
}

private final class LockedFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []
    var isEmpty: Bool { lock.withLock { errors.isEmpty } }
    func append(_ error: Error) { lock.withLock { errors.append(error) } }
}
