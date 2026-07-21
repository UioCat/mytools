import Foundation
import XCTest
@testable import MacToolsCore

final class PayloadStoreTests: XCTestCase {
    func testPNGUsesSHA256ContentAddressedPathAndDeduplicates() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PayloadStore(rootDirectory: root)
        let data = pngData(suffix: 7)

        let first = try store.storePNG(data)
        let second = try store.storePNG(data)

        XCTAssertTrue(first.wasCreated)
        XCTAssertFalse(second.wasCreated)
        XCTAssertEqual(first.id, ClipboardContentHasher.sha256String(for: data))
        XCTAssertEqual(first.relativePath, "objects/sha256/\(String(first.id.prefix(2)))/\(first.id).png")
        XCTAssertEqual(first, second.withCreationFlag(first.wasCreated))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.fileURL(for: first.relativePath))), data)
    }

    func testStoreCreatesManifestAndOwnerOnlyDirectories() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PayloadStore(rootDirectory: root)

        let descriptor = try store.storePNG(pngData(suffix: 8))
        let objectURL = try XCTUnwrap(store.fileURL(for: descriptor.relativePath))

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("store.json").path))
        XCTAssertEqual(try permissions(at: root), 0o700)
        XCTAssertEqual(try permissions(at: objectURL), 0o600)
    }

    func testInvalidPNGIsRejectedBeforeCreatingStorage() throws {
        let root = makeTemporaryRoot()
        let store = PayloadStore(rootDirectory: root)

        XCTAssertThrowsError(try store.storePNG(Data([1, 2, 3]))) { error in
            XCTAssertEqual(error as? PayloadStoreError, .invalidPNG)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testCorruptedExistingObjectIsVerifiedAndRepairedBeforeReuse() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PayloadStore(rootDirectory: root)
        let data = pngData(suffix: 11)
        let first = try store.storePNG(data)
        let url = try XCTUnwrap(store.fileURL(for: first.relativePath))
        try Data("corrupted".utf8).write(to: url, options: [.atomic])

        let repaired = try store.storePNG(data)

        XCTAssertFalse(repaired.wasCreated)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(ClipboardContentHasher.sha256String(for: try Data(contentsOf: url)), first.id)
    }

    func testStagingCleanupRemovesOnlyFilesOlderThanCutoff() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PayloadStore(rootDirectory: root)
        _ = try store.storePNG(pngData(suffix: 9))
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let old = staging.appendingPathComponent("old.tmp")
        let recent = staging.appendingPathComponent("recent.tmp")
        try Data([1]).write(to: old)
        try Data([2]).write(to: recent)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: recent.path)

        try store.removeStagingFiles(olderThan: Date(timeIntervalSince1970: 50))

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PayloadStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func pngData(suffix: UInt8) -> Data {
        var data = Data(base64Encoded: Self.onePixelPNGBase64)!
        data.append(suffix)
        return data
    }

    private static let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}

private extension PayloadObjectDescriptor {
    func withCreationFlag(_ wasCreated: Bool) -> PayloadObjectDescriptor {
        PayloadObjectDescriptor(
            id: id,
            contentHash: contentHash,
            relativePath: relativePath,
            format: format,
            byteCount: byteCount,
            wasCreated: wasCreated
        )
    }
}
