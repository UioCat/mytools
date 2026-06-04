import Foundation
import XCTest
@testable import MacToolsCore

final class FileCacheTests: XCTestCase {
    func testStoresImageDataWithStableExtension() throws {
        let root = makeTemporaryRoot()
        defer { removeTemporaryRoot(root) }
        let cache = FileCache(rootDirectory: root)
        let data = Data([1, 2, 3, 4])

        let result = try cache.store(data: data, preferredExtension: "png")

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.fileURL.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: result.fileURL), data)
    }

    func testStoreNormalizesLeadingDotExtension() throws {
        let root = makeTemporaryRoot()
        defer { removeTemporaryRoot(root) }
        let cache = FileCache(rootDirectory: root)

        let result = try cache.store(data: Data([1]), preferredExtension: ".tiff")

        XCTAssertEqual(result.fileURL.pathExtension, "tiff")
    }

    func testReportsStorageUsage() throws {
        let root = makeTemporaryRoot()
        defer { removeTemporaryRoot(root) }
        let cache = FileCache(rootDirectory: root)
        _ = try cache.store(data: Data(repeating: 1, count: 12), preferredExtension: "png")

        XCTAssertEqual(try cache.totalBytes(), 12)
    }

    func testReportsZeroBytesWhenRootDoesNotExist() throws {
        let root = makeTemporaryRoot()
        let cache = FileCache(rootDirectory: root)

        XCTAssertEqual(try cache.totalBytes(), 0)
    }

    func testRemoveAllRemovesRootAndAllowsMissingRoot() throws {
        let root = makeTemporaryRoot()
        let cache = FileCache(rootDirectory: root)
        _ = try cache.store(data: Data([1, 2, 3]), preferredExtension: "png")

        try cache.removeAll()
        try cache.removeAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeTemporaryRoot(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }
}
