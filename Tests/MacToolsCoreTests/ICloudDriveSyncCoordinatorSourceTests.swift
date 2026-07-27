import Foundation
import XCTest

final class ICloudDriveSyncCoordinatorSourceTests: XCTestCase {
    func testSyncCycleUsesMetadataDraftsBeforeOnDemandContentPreparation() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/Sync/DriveSyncCycleRunner.swift"
        )

        XCTAssertEqual(
            source.components(separatedBy: "localRepository.exportDraft(").count - 1,
            2
        )
        XCTAssertFalse(source.contains("localRepository.exportBundle("))
        XCTAssertFalse(source.contains("SyncExportContentCache"))
        XCTAssertTrue(source.contains("store.prepareContents("))
        XCTAssertTrue(source.contains("preparedDraft.contentDescriptors"))
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

    func testSyncCycleUsesOneFullInventoryScanSiteAndCachesStableCycles() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/Sync/DriveSyncCycleRunner.swift"
        )

        XCTAssertEqual(
            source.components(separatedBy: "store.storageInventory()").count - 1,
            1
        )
        XCTAssertFalse(source.contains("store.storedObjects()"))
        XCTAssertFalse(source.contains("store.usage("))
        XCTAssertTrue(source.contains("cachedInventoryIsFresh"))
        XCTAssertTrue(source.contains("cachedReplicasByDeviceID:"))
        XCTAssertTrue(source.contains("writeWithMetadataDelta("))
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

    func testCoordinatorGuardsRunningCyclesAndPublishedResultsWithLease() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift"
        )

        XCTAssertTrue(source.contains("private struct CycleLease"))
        XCTAssertTrue(source.contains("SyncCycleCancellation"))
        XCTAssertTrue(source.contains("try cancellation.check()"))
        XCTAssertTrue(source.contains("guard isCurrent(lease) else { return }"))
        XCTAssertTrue(source.contains("configuration.scheduleToken != lease.token"))
    }

    func testCoordinatorReconcilesCredentialInsideCoordinatedSyncAndBeforeDeviceRemoval() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/Sync/ICloudDriveSyncCoordinator.swift"
        )

        XCTAssertTrue(source.contains("private let credentialSyncEngine: CredentialSyncEngine"))
        XCTAssertTrue(source.contains("try synchronizeCredential(at: coordinatedRoot)"))
        XCTAssertTrue(source.contains("store.removedDeviceIDs(generation: generation)"))

        let removeStart = try XCTUnwrap(
            source.range(of: "    func removeDevice(_ removedDeviceID: String)")
        )
        let runCyclesStart = try XCTUnwrap(
            source.range(
                of: "    private func runCycles()",
                range: removeStart.upperBound..<source.endIndex
            )
        )
        let removeBody = source[removeStart.lowerBound..<runCyclesStart.lowerBound]
        let preserveCredential = try XCTUnwrap(
            removeBody.range(of: "credentialSyncEngine.synchronize(")
        )
        let writeRemoval = try XCTUnwrap(
            removeBody.range(of: "store.writeRemovedDevice(")
        )
        XCTAssertLessThan(preserveCredential.lowerBound, writeRemoval.lowerBound)
        let publishTakeover = try XCTUnwrap(
            removeBody.range(of: "forceWrite: true")
        )
        let removeDriveReplica = try XCTUnwrap(
            removeBody.range(of: "store.removeDeviceData(")
        )
        let removeCredentialReplica = try XCTUnwrap(
            removeBody.range(of: ".removeReplica(deviceID: removedDeviceID)")
        )
        XCTAssertLessThan(writeRemoval.lowerBound, publishTakeover.lowerBound)
        XCTAssertLessThan(publishTakeover.lowerBound, removeDriveReplica.lowerBound)
        XCTAssertLessThan(removeDriveReplica.lowerBound, removeCredentialReplica.lowerBound)
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
