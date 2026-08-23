import Foundation
import XCTest
@testable import MacTools

final class SyncStoreProcessLockTests: XCTestCase {
    func testSameRootCannotAcquireNestedProcessLock() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = SyncStoreProcessLock()
        let second = SyncStoreProcessLock()

        let outer = try first.withLock(for: root) {
            try second.withLock(for: root) { "unexpected" } == nil
        }

        XCTAssertEqual(outer, true)
    }

    func testDifferentRootsUseIndependentProcessLocks() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = SyncStoreProcessLock()
        let second = SyncStoreProcessLock()

        let result = try first.withLock(for: base.appendingPathComponent("a")) {
            try second.withLock(for: base.appendingPathComponent("b")) { "acquired" }
        }

        XCTAssertEqual(try XCTUnwrap(try XCTUnwrap(result)), "acquired")
    }
}
