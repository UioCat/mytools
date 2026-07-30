import Foundation
import XCTest
@testable import MacTools

final class PasteActivationAttemptTests: XCTestCase {
    @MainActor
    func testReplacingMissingTargetAttemptCancelsPendingFallbackPaste() async throws {
        let oldWait = ControlledFallbackWait()
        let newWait = ControlledFallbackWait()
        var currentAttempt: PasteActivationAttempt?
        var pasteCount = 0

        let oldAttempt = PasteActivationAttempt(
            targetApplication: nil,
            notificationCenter: NotificationCenter(),
            logger: makeTestLogger(),
            fallbackWait: { await oldWait.suspend() },
            paste: { pasteCount += 1 },
            onFinish: { attempt in
                guard currentAttempt === attempt else { return }
                currentAttempt = nil
            }
        )
        currentAttempt = oldAttempt
        let oldTask = try XCTUnwrap(oldAttempt.start())
        await oldWait.waitUntilSuspended()

        oldAttempt.cancel()
        let newAttempt = PasteActivationAttempt(
            targetApplication: nil,
            notificationCenter: NotificationCenter(),
            logger: makeTestLogger(),
            fallbackWait: { await newWait.suspend() },
            paste: { pasteCount += 1 },
            onFinish: { attempt in
                guard currentAttempt === attempt else { return }
                currentAttempt = nil
            }
        )
        currentAttempt = newAttempt
        let newTask = try XCTUnwrap(newAttempt.start())
        await newWait.waitUntilSuspended()

        await oldWait.resume()
        await oldTask.value

        XCTAssertEqual(pasteCount, 0)
        XCTAssertTrue(currentAttempt === newAttempt)

        newAttempt.cancel()
        await newWait.resume()
        await newTask.value
    }
}

private actor ControlledFallbackWait {
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        isSuspended = true
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
