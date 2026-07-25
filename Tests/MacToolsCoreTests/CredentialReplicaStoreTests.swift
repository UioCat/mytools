import Foundation
import XCTest
@testable import MacToolsCore

final class CredentialReplicaStoreTests: XCTestCase {
    private let codec = CredentialEnvelopeCodec()
    private let deviceA = "00000000-0000-0000-0000-00000000000A"
    private let deviceB = "00000000-0000-0000-0000-00000000000B"

    func testEachDeviceWritesAndReadsItsOwnReplica() throws {
        try withStore { store, root in
            let first = try envelope(value: "first", counter: 1, deviceID: deviceA)
            let second = try envelope(value: "second", counter: 2, deviceID: deviceB)

            try store.write(first, deviceID: deviceA)
            try store.write(second, deviceID: deviceB)
            let scan = try store.scan(excluding: [])

            XCTAssertEqual(scan.replicas, [
                CredentialReplica(deviceID: deviceA, envelope: first),
                CredentialReplica(deviceID: deviceB, envelope: second)
            ])
            XCTAssertTrue(scan.failures.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "credentials/replicas/\(deviceA).v1.json"
                ).path
            ))
        }
    }

    func testRemovedDeviceReplicaIsExcluded() throws {
        try withStore { store, _ in
            try store.write(
                envelope(value: "first", counter: 1, deviceID: deviceA),
                deviceID: deviceA
            )
            try store.write(
                envelope(value: "second", counter: 2, deviceID: deviceB),
                deviceID: deviceB
            )

            let scan = try store.scan(excluding: [deviceB])

            XCTAssertEqual(scan.replicas.map(\.deviceID), [deviceA])
        }
    }

    func testCorruptedReplicaIsIsolatedFromHealthyPeer() throws {
        try withStore { store, root in
            let healthy = try envelope(value: "healthy", counter: 1, deviceID: deviceA)
            try store.write(healthy, deviceID: deviceA)
            let directory = root.appendingPathComponent(
                "credentials/replicas",
                isDirectory: true
            )
            try Data("not-json".utf8).write(
                to: directory.appendingPathComponent("\(deviceB).v1.json")
            )

            let scan = try store.scan(excluding: [])

            XCTAssertEqual(scan.replicas, [
                CredentialReplica(deviceID: deviceA, envelope: healthy)
            ])
            XCTAssertEqual(scan.failures, [
                CredentialReplicaFailure(
                    deviceID: deviceB,
                    error: .unreadableReplica(deviceB)
                )
            ])
        }
    }

    func testInvalidDeviceFilenameIsReported() throws {
        try withStore { store, root in
            let directory = root.appendingPathComponent(
                "credentials/replicas",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data("{}".utf8).write(
                to: directory.appendingPathComponent("not-a-device.v1.json")
            )

            let scan = try store.scan(excluding: [])

            XCTAssertTrue(scan.replicas.isEmpty)
            XCTAssertEqual(scan.failures, [
                CredentialReplicaFailure(
                    deviceID: "not-a-device",
                    error: .invalidDeviceID("not-a-device")
                )
            ])
        }
    }

    func testDeviceCanRepublishEnvelopeOriginatedByPeer() throws {
        try withStore { store, _ in
            let envelope = try envelope(value: "value", counter: 1, deviceID: deviceA)

            try store.write(envelope, deviceID: deviceB)

            XCTAssertEqual(
                try store.scan(excluding: []).replicas,
                [CredentialReplica(deviceID: deviceB, envelope: envelope)]
            )
        }
    }

    func testTwoClientsConvergeOnDeletionWithoutRevivingOldValue() throws {
        try withStore { store, _ in
            let active = try envelope(value: "active", counter: 1, deviceID: deviceA)
            try store.write(active, deviceID: deviceA)
            let clientBInitial = try CredentialReconciler().winner(
                local: nil,
                replicas: store.scan(excluding: []).replicas,
                for: .bailianAPIKey
            )
            XCTAssertEqual(clientBInitial?.record.value, "active")

            let deleted = try envelope(value: nil, counter: 2, deviceID: deviceB)
            try store.write(deleted, deviceID: deviceB)
            let clientAFinal = try CredentialReconciler().winner(
                local: active,
                replicas: store.scan(excluding: []).replicas,
                for: .bailianAPIKey
            )

            XCTAssertEqual(clientAFinal?.record.state, .deleted)
            XCTAssertNil(clientAFinal?.record.value)
        }
    }

    private func withStore(
        _ operation: (CredentialReplicaStore, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(CredentialReplicaStore(rootURL: root), root)
    }

    private func envelope(
        value: String?,
        counter: Int64,
        deviceID: String
    ) throws -> CredentialEnvelope {
        try codec.seal(
            value: value,
            for: .bailianAPIKey,
            clock: ClipboardFieldClock(counter: counter, deviceID: deviceID),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(counter))
        )
    }
}
