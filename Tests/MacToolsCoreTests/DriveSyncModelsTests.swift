import XCTest
@testable import MacToolsCore

final class DriveSyncModelsTests: XCTestCase {
    func testDefaultStorageLimitIs512MiB() {
        XCTAssertEqual(SyncStorageLimit.default, .megabytes512)
        XCTAssertEqual(SyncStorageLimit.default.byteLimit, 536_870_912)
        XCTAssertEqual(SyncRetentionPolicy.defaultOrdinaryHistoryLimit, 500)
        XCTAssertEqual(SyncRetentionPolicy.maximumImageBytes, 67_108_864)
    }

    func testSnapshotEncodingIsCompactDeterministicAndRoundTrips() throws {
        let snapshot = SyncClipboardSnapshot(
            deviceID: "device-b",
            generation: 3,
            revision: 42,
            records: [
                SyncClipboardRecord(
                    recordName: "record-1",
                    contentID: String(repeating: "a", count: 64),
                    kind: .text,
                    displayTitle: "Example",
                    searchableText: "Example",
                    sourceApp: "Example",
                    createdAt: Date(timeIntervalSince1970: 100),
                    lastCapturedAt: Date(timeIntervalSince1970: 110),
                    lastUsedAt: Date(timeIntervalSince1970: 120),
                    retentionAt: Date(timeIntervalSince1970: 120),
                    useCount: 2,
                    isPinned: false,
                    isFavorite: true,
                    favoriteClock: ClipboardFieldClock(counter: 4, deviceID: "device-b"),
                    pinnedClock: .zero
                )
            ]
        )

        let first = try SyncSnapshotCodec.encode(snapshot)
        let second = try SyncSnapshotCodec.encode(snapshot)

        XCTAssertEqual(first, second)
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("\n"))
        XCTAssertEqual(SyncSnapshotCodec.digest(first).count, 64)
        XCTAssertEqual(
            try SyncSnapshotCodec.decode(SyncClipboardSnapshot.self, from: first),
            snapshot
        )
    }

    func testRetentionEvictsOldestOrdinaryContentAtGlobalLimit() {
        let base = Date(timeIntervalSince1970: 1_000)
        let candidates = (0...500).map { index in
            candidate(
                id: String(format: "%03d", index),
                bytes: 1,
                createdAt: base.addingTimeInterval(TimeInterval(index)),
                retentionAt: base.addingTimeInterval(TimeInterval(index))
            )
        }

        let decision = SyncRetentionPolicy.decide(
            candidates: candidates,
            metadataBytes: 0,
            capacityLimitBytes: 10_000,
            generation: 1,
            deviceID: "device-a",
            now: base
        )

        XCTAssertEqual(decision.ordinaryCount, 500)
        XCTAssertEqual(decision.evictions.map(\.contentID), ["000"])
        XCTAssertEqual(decision.evictions.first?.reason, .historyLimit)
        XCTAssertFalse(decision.keptContentIDs.contains("000"))
    }

    func testRetentionNeverEvictsProtectedContentAndPausesImagesWhenItFillsCapacity() {
        let now = Date(timeIntervalSince1970: 2_000)
        let protected = candidate(
            id: "protected",
            bytes: 100,
            createdAt: now,
            retentionAt: now,
            isFavorite: true
        )
        let ordinary = candidate(
            id: "ordinary",
            bytes: 25,
            createdAt: now.addingTimeInterval(1),
            retentionAt: now.addingTimeInterval(1)
        )

        let decision = SyncRetentionPolicy.decide(
            candidates: [ordinary, protected],
            metadataBytes: 10,
            capacityLimitBytes: 100,
            generation: 2,
            deviceID: "device-a",
            now: now
        )

        XCTAssertEqual(decision.keptContentIDs, ["protected"])
        XCTAssertEqual(decision.evictions.map(\.contentID), ["ordinary"])
        XCTAssertEqual(decision.evictions.first?.reason, .capacityLimit)
        XCTAssertEqual(decision.protectedBytes, 110)
        XCTAssertTrue(decision.shouldPauseImageUploads)
    }

    func testPhysicalObjectsWaitingForGarbageCollectionPauseNewImages() {
        let decision = SyncRetentionPolicy.decide(
            candidates: [],
            metadataBytes: 0,
            capacityLimitBytes: 100,
            generation: 1,
            deviceID: "device-a",
            now: Date(timeIntervalSince1970: 1)
        )

        XCTAssertTrue(SyncRetentionPolicy.mustPauseImageUploads(
            decision: decision,
            currentUsedBytes: 90,
            newObjectBytes: 11,
            projectedMetadataBytes: 0,
            capacityLimitBytes: 100
        ))
        XCTAssertFalse(SyncRetentionPolicy.mustPauseImageUploads(
            decision: decision,
            currentUsedBytes: 90,
            newObjectBytes: 10,
            projectedMetadataBytes: 0,
            capacityLimitBytes: 100
        ))
    }

    func testDuplicateContentUsesNewestActivityAndWinningProtectionClock() {
        let old = candidate(
            id: "same",
            bytes: 10,
            createdAt: Date(timeIntervalSince1970: 50),
            retentionAt: Date(timeIntervalSince1970: 100),
            isFavorite: true,
            favoriteClock: ClipboardFieldClock(counter: 1, deviceID: "device-a")
        )
        let new = candidate(
            id: "same",
            bytes: 12,
            createdAt: Date(timeIntervalSince1970: 60),
            retentionAt: Date(timeIntervalSince1970: 200),
            isFavorite: false,
            favoriteClock: ClipboardFieldClock(counter: 2, deviceID: "device-b")
        )

        let decision = SyncRetentionPolicy.decide(
            candidates: [old, new],
            metadataBytes: 0,
            capacityLimitBytes: 100,
            ordinaryHistoryLimit: 0,
            generation: 1,
            deviceID: "device-c",
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertTrue(decision.keptContentIDs.isEmpty)
        XCTAssertEqual(decision.evictions.count, 1)
        XCTAssertEqual(decision.evictions[0].observedRetentionAt, new.retentionAt)
        XCTAssertEqual(decision.evictions[0].observedFavoriteClock, new.favoriteClock)
    }

    func testEqualProtectionClockConservativelyKeepsProtectedValue() {
        let clock = ClipboardFieldClock(counter: 1, deviceID: "device-a")
        let protected = candidate(
            id: "same",
            bytes: 10,
            createdAt: Date(timeIntervalSince1970: 1),
            retentionAt: Date(timeIntervalSince1970: 1),
            isFavorite: true,
            favoriteClock: clock
        )
        let unprotected = candidate(
            id: "same",
            bytes: 10,
            createdAt: Date(timeIntervalSince1970: 1),
            retentionAt: Date(timeIntervalSince1970: 1),
            isFavorite: false,
            favoriteClock: clock
        )

        let firstOrder = protected.merging(unprotected)
        let secondOrder = unprotected.merging(protected)

        XCTAssertTrue(firstOrder.isFavorite)
        XCTAssertTrue(secondOrder.isFavorite)
        XCTAssertEqual(firstOrder, secondOrder)
    }

    func testStaleEvictionIsInvalidatedByActivityOrProtection() {
        let observedAt = Date(timeIntervalSince1970: 100)
        let eviction = SyncEvictionRecord(
            contentID: "same",
            reason: .capacityLimit,
            deviceID: "device-a",
            generation: 1,
            observedRetentionAt: observedAt,
            observedFavoriteClock: .zero,
            observedPinnedClock: .zero,
            evictedAt: observedAt
        )

        XCTAssertTrue(eviction.isEffective(for: candidate(
            id: "same",
            bytes: 1,
            createdAt: observedAt,
            retentionAt: observedAt
        )))
        XCTAssertFalse(eviction.isEffective(for: candidate(
            id: "same",
            bytes: 1,
            createdAt: observedAt,
            retentionAt: observedAt.addingTimeInterval(1)
        )))
        XCTAssertFalse(eviction.isEffective(for: candidate(
            id: "same",
            bytes: 1,
            createdAt: observedAt,
            retentionAt: observedAt,
            isPinned: true,
            pinnedClock: ClipboardFieldClock(counter: 1, deviceID: "device-b")
        )))
    }

    private func candidate(
        id: String,
        bytes: Int64,
        createdAt: Date,
        retentionAt: Date,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        favoriteClock: ClipboardFieldClock = .zero,
        pinnedClock: ClipboardFieldClock = .zero
    ) -> SyncRetentionCandidate {
        SyncRetentionCandidate(
            contentID: id,
            kind: .text,
            byteCount: bytes,
            createdAt: createdAt,
            retentionAt: retentionAt,
            isFavorite: isFavorite,
            isPinned: isPinned,
            favoriteClock: favoriteClock,
            pinnedClock: pinnedClock
        )
    }
}
