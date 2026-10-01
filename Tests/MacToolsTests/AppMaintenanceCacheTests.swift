import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class AppMaintenanceCacheTests: XCTestCase {
    func testStartupMaintenanceEnforcesReducedBudgetAndKeepsFavorites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let payloads = PayloadStore(rootDirectory: root.appendingPathComponent("payloads"))
        let repository = ClipboardRepository(database: try MacToolsDatabase.at(root.appendingPathComponent("test.sqlite")), payloadStore: payloads)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
        let normal = item(favorite: false)
        let favorite = item(favorite: true)
        try repository.upsertPNG(normal, data: png)
        try repository.upsertPNG(favorite, data: png + Data([1]))
        repository.configureCacheLimit(megabytes: 0)
        let worker = AppMaintenanceWorker(repository: repository, payloadStore: payloads, usesPersistentDatabase: true, logger: Logger(debugLogDirectory: root.appendingPathComponent("logs")))

        await worker.run()

        XCTAssertNil(try repository.item(id: normal.id))
        XCTAssertNotNil(try repository.item(id: favorite.id))
        XCTAssertEqual(try payloads.objectRelativePaths().count, 1)
    }

    private func item(favorite: Bool) -> ClipboardItem {
        ClipboardItem(id: UUID(), kind: .imageData, displayTitle: "Synthetic image", searchableText: "Synthetic image", text: nil,
            originalPath: nil, cachedFilePath: nil, thumbnailPath: nil, sourceApp: nil, contentHash: UUID().uuidString,
            createdAt: Date(timeIntervalSince1970: 100), lastUsedAt: nil, useCount: 0, isPinned: false, isFavorite: favorite, tags: [])
    }
}
