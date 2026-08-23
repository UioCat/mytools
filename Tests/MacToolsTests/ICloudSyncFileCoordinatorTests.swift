import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class ICloudSyncFileCoordinatorTests: XCTestCase {
    func testManifestPublicationUsesCoordinatedCurrentVersionAndReadback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manifest.json")
        let coordinator = ICloudSyncFileCoordinator()
        let firstData = Data("first".utf8)
        let secondData = Data("second".utf8)

        let first = try coordinator.coordinateManifest(at: url) { versions in
            XCTAssertTrue(versions.isEmpty)
            return .publish(data: firstData, baseVersionID: nil)
        }
        let second = try coordinator.coordinateManifest(at: url) { versions in
            let current = try XCTUnwrap(versions.first(where: \.isCurrent))
            XCTAssertEqual(current.data, firstData)
            return .publish(data: secondData, baseVersionID: current.versionID)
        }

        XCTAssertTrue(first.didWrite)
        XCTAssertTrue(second.didWrite)
        XCTAssertEqual(second.data, secondData)
        XCTAssertEqual(try coordinator.readData(at: url), secondData)
    }

    func testKeepingCurrentManifestDoesNotRewriteIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manifest.json")
        let coordinator = ICloudSyncFileCoordinator()
        let data = Data("stable".utf8)
        try coordinator.writeData(data, to: url)

        let result = try coordinator.coordinateManifest(at: url) { versions in
            .keep(versionID: try XCTUnwrap(versions.first?.versionID))
        }

        XCTAssertFalse(result.didWrite)
        XCTAssertEqual(result.data, data)
    }
}
