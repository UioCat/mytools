import Foundation
import XCTest

final class ICloudDriveSyncCoordinatorSourceTests: XCTestCase {
    func testSyncCycleReusesContentAcrossTwoExportsWithoutThirdFullExport() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/Sync/DriveSyncCycleRunner.swift"
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

    func testSyncCycleOnlyAppliesPeerReplicasWithoutMatchingReceipts() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/Sync/DriveSyncCycleRunner.swift"
        )

        XCTAssertTrue(source.contains("let receiptsByDeviceID"))
        XCTAssertTrue(source.contains("let unappliedPeerReplicas"))
        XCTAssertEqual(
            source.components(separatedBy: "for replica in unappliedPeerReplicas").count - 1,
            3
        )
    }

    func testSyncCycleUsesAtMostTwoUnifiedStorageInventoryScans() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/Sync/DriveSyncCycleRunner.swift"
        )

        XCTAssertEqual(
            source.components(separatedBy: "store.storageInventory()").count - 1,
            2
        )
        XCTAssertFalse(source.contains("store.storedObjects()"))
        XCTAssertFalse(source.contains("store.usage("))
    }

    func testCoordinatorDelegatesSingleCycleWorkToCoreRunner() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift"
        )

        XCTAssertTrue(source.contains("private let cycleRunner: DriveSyncCycleRunner"))
        XCTAssertTrue(source.contains("try cycleRunner.run("))
        XCTAssertFalse(source.contains("localRepository.exportBundle("))
        XCTAssertFalse(source.contains("store.storageInventory()"))
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
