import Foundation
import XCTest
@testable import MacToolsCore

final class CredentialEnvelopeCodecTests: XCTestCase {
    private let codec = CredentialEnvelopeCodec()
    private let clock = ClipboardFieldClock(counter: 7, deviceID: "device-a")
    private let date = Date(timeIntervalSince1970: 1_753_430_400.125)

    func testActiveEnvelopeRoundTripsNormalizedValue() throws {
        let envelope = try codec.seal(
            value: "  placeholder-value\n",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )

        let record = try codec.open(envelope, for: .bailianAPIKey)

        XCTAssertEqual(record.state, .active)
        XCTAssertEqual(record.value, "placeholder-value")
        XCTAssertEqual(record.clock, clock)
        XCTAssertEqual(record.updatedAt, date)
    }

    func testDeletedEnvelopeRoundTripsWithoutValue() throws {
        let envelope = try codec.seal(
            value: " \n ",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )

        let record = try codec.open(envelope, for: .bailianAPIKey)

        XCTAssertEqual(record.state, .deleted)
        XCTAssertNil(record.value)
    }

    func testSameValueUsesFreshNonce() throws {
        let first = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )
        let second = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )

        XCTAssertNotEqual(first.sealedBox, second.sealedBox)
        XCTAssertEqual(
            try codec.open(first, for: .bailianAPIKey),
            try codec.open(second, for: .bailianAPIKey)
        )
    }

    func testJSONEncodingRoundTripsEnvelope() throws {
        let envelope = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )

        let data = try codec.encode(envelope)

        XCTAssertEqual(try codec.decode(data), envelope)
    }

    func testUnsupportedSchemaAndKeyVersionsAreRejected() throws {
        let original = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )
        var wrongSchema = original
        wrongSchema.schemaVersion = 2
        var wrongKey = original
        wrongKey.keyVersion = 2

        XCTAssertThrowsError(try codec.open(wrongSchema, for: .bailianAPIKey)) {
            XCTAssertEqual($0 as? CredentialEnvelopeCodecError, .unsupportedSchema(2))
        }
        XCTAssertThrowsError(try codec.open(wrongKey, for: .bailianAPIKey)) {
            XCTAssertEqual($0 as? CredentialEnvelopeCodecError, .unsupportedKeyVersion(2))
        }
    }

    func testWrongCredentialIDIsRejected() throws {
        var envelope = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )
        envelope.credentialID = "different.credential"

        XCTAssertThrowsError(try codec.open(envelope, for: .bailianAPIKey)) {
            XCTAssertEqual(
                $0 as? CredentialEnvelopeCodecError,
                .unexpectedCredentialID("different.credential")
            )
        }
    }

    func testAuthenticatedHeaderMutationIsRejected() throws {
        var envelope = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )
        envelope.clock.counter += 1

        XCTAssertThrowsError(try codec.open(envelope, for: .bailianAPIKey)) {
            XCTAssertEqual($0 as? CredentialEnvelopeCodecError, .authenticationFailed)
        }
    }

    func testCiphertextOrTagMutationIsRejected() throws {
        var envelope = try codec.seal(
            value: "placeholder-value",
            for: .bailianAPIKey,
            clock: clock,
            updatedAt: date
        )
        envelope.sealedBox[envelope.sealedBox.index(before: envelope.sealedBox.endIndex)] ^= 0x01

        XCTAssertThrowsError(try codec.open(envelope, for: .bailianAPIKey)) {
            XCTAssertEqual($0 as? CredentialEnvelopeCodecError, .authenticationFailed)
        }
    }

    func testInvalidCombinedRepresentationIsRejected() throws {
        let envelope = CredentialEnvelope(
            schemaVersion: 1,
            keyVersion: 1,
            credentialID: CredentialKey.bailianAPIKey.rawValue,
            clock: clock,
            sealedBox: Data([0x01, 0x02])
        )

        XCTAssertThrowsError(try codec.open(envelope, for: .bailianAPIKey)) {
            XCTAssertEqual($0 as? CredentialEnvelopeCodecError, .invalidSealedBox)
        }
    }
}
