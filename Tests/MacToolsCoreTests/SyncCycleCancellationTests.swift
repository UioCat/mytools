import XCTest
@testable import MacToolsCore

final class SyncCycleCancellationTests: XCTestCase {
    func testActiveCancellationCheckSucceeds() throws {
        try SyncCycleCancellation().check()
    }

    func testCancelledCheckThrowsDedicatedError() {
        XCTAssertThrowsError(
            try SyncCycleCancellation(isCancelled: { true }).check()
        ) { error in
            XCTAssertEqual(
                error as? SyncCycleCancellationError,
                .cancelled
            )
        }
    }
}
