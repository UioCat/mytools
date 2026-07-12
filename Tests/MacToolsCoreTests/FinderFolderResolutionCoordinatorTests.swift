import XCTest
@testable import MacToolsCore

@MainActor
final class FinderFolderResolutionCoordinatorTests: XCTestCase {
    func testSlowFirstRequestFollowedByFastSecondRequestCompletesOnlySecondCallback() async {
        let coordinator = FinderFolderResolutionCoordinator()
        let firstStarted = expectation(description: "first operation started")
        let firstFinished = expectation(description: "first operation finished")
        let firstCallback = expectation(description: "first callback is suppressed")
        firstCallback.isInverted = true
        let secondCallback = expectation(description: "second callback completes")
        var firstContinuation: CheckedContinuation<Void, Never>?

        coordinator.replace(
            operation: {
                await withCheckedContinuation { continuation in
                    firstContinuation = continuation
                    firstStarted.fulfill()
                }
                firstFinished.fulfill()
                return "first"
            },
            completion: { value in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(value, "first")
                firstCallback.fulfill()
            }
        )
        await fulfillment(of: [firstStarted], timeout: 1)

        coordinator.replace(
            operation: { "second" },
            completion: { value in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(value, "second")
                secondCallback.fulfill()
            }
        )
        await fulfillment(of: [secondCallback], timeout: 1)

        firstContinuation?.resume()
        await fulfillment(of: [firstFinished, firstCallback], timeout: 0.2)
    }

    func testCancellingSlowRequestPreventsItsCallback() async {
        let coordinator = FinderFolderResolutionCoordinator()
        let operationStarted = expectation(description: "operation started")
        let operationFinished = expectation(description: "operation finished")
        let callback = expectation(description: "callback is suppressed")
        callback.isInverted = true
        var continuation: CheckedContinuation<Void, Never>?

        coordinator.replace(
            operation: {
                await withCheckedContinuation { storedContinuation in
                    continuation = storedContinuation
                    operationStarted.fulfill()
                }
                operationFinished.fulfill()
                return "cancelled"
            },
            completion: { _ in
                callback.fulfill()
            }
        )
        await fulfillment(of: [operationStarted], timeout: 1)

        coordinator.cancel()
        continuation?.resume()

        await fulfillment(of: [operationFinished, callback], timeout: 0.2)
    }
}
