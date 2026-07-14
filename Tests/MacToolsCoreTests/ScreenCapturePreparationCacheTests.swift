import XCTest
@testable import MacToolsCore

final class ScreenCapturePreparationCacheTests: XCTestCase {
    @MainActor
    func testInvalidationCancelsOldLoadAndKeepsRapidRestartCached() async throws {
        var loadCount = 0
        let cache = ScreenCapturePreparationCache<Int> {
            loadCount += 1
            let value = loadCount
            if value == 1 {
                try await Task.sleep(for: .seconds(10))
            }
            return value
        }

        let firstLoad = Task {
            try await cache.value()
        }
        while loadCount == 0 {
            await Task.yield()
        }

        cache.invalidate()
        let restartedValue = try await cache.value()

        do {
            _ = try await firstLoad.value
            XCTFail("Expected invalidation to cancel the previous load")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(restartedValue, 2)
        let cachedValue = try await cache.value()
        XCTAssertEqual(cachedValue, 2)
        XCTAssertEqual(loadCount, 2)
    }
}
