import Foundation
import XCTest
@testable import MacToolsCore

final class SyncManifestConflictResolverTests: XCTestCase {
    func testHigherMonotonicRevisionWinsOverItsAncestor() {
        let ancestor = candidate(
            id: "1885",
            revision: 1_885,
            seenRevisions: ["device-a": 1_885, "device-b": 8_212],
            isCurrent: false
        )
        let current = candidate(
            id: "1887",
            revision: 1_887,
            seenRevisions: ["device-a": 1_887, "device-b": 8_217],
            isCurrent: true
        )

        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([ancestor, current]),
            .keep(versionID: "1887")
        )
    }

    func testIncomparableBranchesRemainUnresolved() {
        let left = candidate(
            id: "left",
            revision: 10,
            seenRevisions: ["device-a": 10, "device-b": 4],
            isCurrent: true
        )
        let right = candidate(
            id: "right",
            revision: 11,
            seenRevisions: ["device-a": 11, "device-b": 3],
            isCurrent: false
        )

        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([left, right]),
            .unresolved
        )
    }

    func testCandidateWithInvalidOwnSeenRevisionCannotWin() {
        let invalid = candidate(
            id: "invalid",
            revision: 12,
            seenRevisions: ["device-a": 11],
            isCurrent: true
        )
        let valid = candidate(
            id: "valid",
            revision: 11,
            seenRevisions: ["device-a": 11],
            isCurrent: false
        )

        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([invalid, valid]),
            .unresolved
        )
    }

    func testDifferentGenerationOrDeviceRemainsUnresolved() {
        let current = candidate(
            id: "current",
            revision: 3,
            seenRevisions: ["device-a": 3],
            isCurrent: true
        )
        var otherGeneration = candidate(
            id: "generation",
            revision: 4,
            seenRevisions: ["device-a": 4],
            isCurrent: false
        )
        otherGeneration.manifest.generation = 2
        var otherDevice = otherGeneration
        otherDevice.manifest.generation = 1
        otherDevice.manifest.deviceID = "device-b"
        otherDevice.manifest.seenRevisions = ["device-b": 4]

        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([current, otherGeneration]),
            .unresolved
        )
        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([current, otherDevice]),
            .unresolved
        )
    }

    func testSupersededLedgerCandidateCanOnlyLoseToCompleteWinner() {
        let lateAncestor = candidate(
            id: "late",
            revision: 4,
            seenRevisions: ["device-a": 4],
            isCurrent: false,
            verification: .supersededLedger(replacedByRevision: 5)
        )
        let winner = candidate(
            id: "winner",
            revision: 5,
            seenRevisions: ["device-a": 5],
            isCurrent: true
        )

        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([lateAncestor, winner]),
            .keep(versionID: "winner")
        )
        XCTAssertEqual(
            SyncManifestConflictResolver.resolve([lateAncestor]),
            .unresolved
        )
    }

    private func candidate(
        id: String,
        revision: Int64,
        seenRevisions: [String: Int64],
        isCurrent: Bool,
        verification: SyncManifestCandidate.Verification = .complete
    ) -> SyncManifestCandidate {
        SyncManifestCandidate(
            versionID: id,
            isCurrent: isCurrent,
            manifest: SyncReplicaManifest(
                deviceID: "device-a",
                generation: 1,
                revision: revision,
                seenRevisions: seenRevisions,
                snapshotDigests: SyncSnapshotDigests(
                    clipboard: "clipboard-\(revision)",
                    preferences: "preferences-\(revision)",
                    tombstones: "tombstones-\(revision)"
                ),
                snapshotDirectory: "g1-r\(revision)-digest",
                updatedAt: Date(timeIntervalSince1970: TimeInterval(revision))
            ),
            manifestDigest: "manifest-\(revision)",
            verification: verification
        )
    }
}
