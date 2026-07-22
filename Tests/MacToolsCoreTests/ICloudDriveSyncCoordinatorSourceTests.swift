import Foundation
import XCTest

final class ICloudDriveSyncCoordinatorSourceTests: XCTestCase {
    func testSyncCycleReusesContentAcrossTwoExportsWithoutThirdFullExport() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift"
        )

        XCTAssertEqual(
            source.components(separatedBy: "localRepository.exportBundle(").count - 1,
            2
        )
        XCTAssertEqual(
            source.components(separatedBy: "contentCache: &exportContentCache").count - 1,
            2
        )
        XCTAssertTrue(source.contains("draft.excludingContentIDs("))
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
