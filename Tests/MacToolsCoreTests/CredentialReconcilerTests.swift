import Foundation
import XCTest
@testable import MacToolsCore

final class CredentialReconcilerTests: XCTestCase {
    private let codec = CredentialEnvelopeCodec()

    func testHighestLogicalClockWinsAcrossLocalAndReplicas() throws {
        let local = try envelope(value: "local", counter: 2, deviceID: "device-a")
        let remote = try envelope(value: "remote", counter: 3, deviceID: "device-b")

        let result = try CredentialReconciler().winner(
            local: local,
            replicas: [
                CredentialReplica(deviceID: "device-b", envelope: remote)
            ],
            for: .bailianAPIKey
        )

        XCTAssertEqual(result?.envelope, remote)
        XCTAssertEqual(result?.record.value, "remote")
    }

    func testDeviceIDBreaksEqualCounterTieDeterministically() throws {
        let first = try envelope(value: "first", counter: 4, deviceID: "device-a")
        let second = try envelope(value: "second", counter: 4, deviceID: "device-b")

        let forward = try CredentialReconciler().winner(
            local: first,
            replicas: [CredentialReplica(deviceID: "device-b", envelope: second)],
            for: .bailianAPIKey
        )
        let reverse = try CredentialReconciler().winner(
            local: second,
            replicas: [CredentialReplica(deviceID: "device-a", envelope: first)],
            for: .bailianAPIKey
        )

        XCTAssertEqual(forward?.record.value, "second")
        XCTAssertEqual(reverse?.record.value, "second")
    }

    func testNewerDeletionPreventsOlderActiveValueFromReviving() throws {
        let active = try envelope(value: "active", counter: 5, deviceID: "device-a")
        let deleted = try envelope(value: nil, counter: 6, deviceID: "device-b")

        let result = try CredentialReconciler().winner(
            local: active,
            replicas: [CredentialReplica(deviceID: "device-b", envelope: deleted)],
            for: .bailianAPIKey
        )

        XCTAssertEqual(result?.record.state, .deleted)
        XCTAssertNil(result?.record.value)
    }

    func testIdenticalRecordWithDifferentNonceIsNotAConflict() throws {
        let first = try envelope(
            value: "same",
            counter: 3,
            deviceID: "device-a",
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let second = try envelope(
            value: "same",
            counter: 3,
            deviceID: "device-a",
            updatedAt: Date(timeIntervalSince1970: 30)
        )

        let result = try CredentialReconciler().winner(
            local: first,
            replicas: [CredentialReplica(deviceID: "device-a", envelope: second)],
            for: .bailianAPIKey
        )

        XCTAssertEqual(result?.record.value, "same")
        XCTAssertEqual(result?.envelope, first)
    }

    func testDifferentRecordsWithSameClockAreRejected() throws {
        let first = try envelope(
            value: "first",
            counter: 3,
            deviceID: "device-a",
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let second = try envelope(
            value: "second",
            counter: 3,
            deviceID: "device-a",
            updatedAt: Date(timeIntervalSince1970: 31)
        )

        XCTAssertThrowsError(
            try CredentialReconciler().winner(
                local: first,
                replicas: [CredentialReplica(deviceID: "device-a", envelope: second)],
                for: .bailianAPIKey
            )
        ) {
            XCTAssertEqual($0 as? CredentialReconcilerError, .conflictingEqualClock)
        }
    }

    func testNoCandidatesReturnsNil() throws {
        XCTAssertNil(
            try CredentialReconciler().winner(
                local: nil,
                replicas: [],
                for: .bailianAPIKey
            )
        )
    }

    private func envelope(
        value: String?,
        counter: Int64,
        deviceID: String,
        updatedAt: Date? = nil
    ) throws -> CredentialEnvelope {
        try codec.seal(
            value: value,
            for: .bailianAPIKey,
            clock: ClipboardFieldClock(counter: counter, deviceID: deviceID),
            updatedAt: updatedAt ?? Date(timeIntervalSince1970: TimeInterval(counter))
        )
    }
}
