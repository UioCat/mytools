import Foundation
import XCTest
@testable import MacToolsCore

final class SyncFileCoordinatorTests: XCTestCase {
    func testDirectCoordinatorPublishesAndReadsBackManifest() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("manifest.json")
        let coordinator = DirectSyncFileCoordinator()
        let expected = Data("published".utf8)

        let result = try coordinator.coordinateManifest(at: url) { versions in
            XCTAssertTrue(versions.isEmpty)
            return .publish(data: expected, baseVersionID: nil)
        }

        XCTAssertEqual(result.data, expected)
        XCTAssertTrue(result.didWrite)
        XCTAssertEqual(try coordinator.readData(at: url), expected)
    }

    func testDirectCoordinatorRejectsStaleBaseVersion() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("manifest.json")
        let coordinator = DirectSyncFileCoordinator()
        try coordinator.writeData(Data("current".utf8), to: url)

        XCTAssertThrowsError(
            try coordinator.coordinateManifest(at: url) { _ in
                .publish(data: Data("new".utf8), baseVersionID: "stale")
            }
        ) { error in
            XCTAssertEqual(error as? DriveSyncStoreError, .fileConflict(url))
        }
        XCTAssertEqual(try coordinator.readData(at: url), Data("current".utf8))
    }

    func testKeepDoesNotRewriteCurrentManifest() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("manifest.json")
        let coordinator = DirectSyncFileCoordinator()
        try coordinator.writeData(Data("current".utf8), to: url)

        let result = try coordinator.coordinateManifest(at: url) { versions in
            .keep(versionID: try XCTUnwrap(versions.first?.versionID))
        }

        XCTAssertEqual(result.data, Data("current".utf8))
        XCTAssertFalse(result.didWrite)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncFileCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
