import XCTest
@testable import MacToolsCore

final class ScreenCapturePreparationCacheTests: XCTestCase {
    @MainActor
    func testSuccessfulValueIsReusedForFiveSecondsThenRefreshed() async throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        var loadCount = 0
        let cache = ScreenCapturePreparationCache<Int>(
            timeToLive: 5,
            now: { currentDate }
        ) {
            loadCount += 1
            return loadCount
        }

        let firstValue = try await cache.value()
        currentDate.addTimeInterval(5)
        let boundaryValue = try await cache.value()
        currentDate.addTimeInterval(0.001)
        let expiredValue = try await cache.value()

        XCTAssertEqual(firstValue, 1)
        XCTAssertEqual(boundaryValue, 1)
        XCTAssertEqual(expiredValue, 2)
        XCTAssertEqual(loadCount, 2)
    }

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

    @MainActor
    func testInvalidatedNonCooperativeLoadCannotReturnItsStaleValue() async throws {
        var loadCount = 0
        var releaseFirstLoad: CheckedContinuation<Void, Never>?
        let cache = ScreenCapturePreparationCache<Int> {
            loadCount += 1
            let value = loadCount
            if value == 1 {
                await withCheckedContinuation { continuation in
                    releaseFirstLoad = continuation
                }
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
        let refreshedValue = try await cache.value()
        releaseFirstLoad?.resume()

        do {
            _ = try await firstLoad.value
            XCTFail("Expected an invalidated load to discard its stale value")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(refreshedValue, 2)
        XCTAssertEqual(loadCount, 2)
    }
}
