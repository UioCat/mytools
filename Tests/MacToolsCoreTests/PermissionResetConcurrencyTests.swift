import XCTest
@testable import MacToolsCore

@MainActor
final class PermissionResetConcurrencyTests: XCTestCase {
    func testServiceCoalescesConcurrentResetRequestsAndAllowsLaterRetry() async throws {
        let resetter = SuspendedPermissionResetter()
        let service = PermissionService(checker: ResetPermissionChecker(), decisionResetter: resetter,
            bundleIdentifierProvider: { "local.synthetic.mactools" })
        let first = Task { try await service.resetPermissionDecisions() }
        await resetter.waitUntilStarted()
        let second = Task { try await service.resetPermissionDecisions() }
        for _ in 0..<100 { await Task.yield() }
        let currentCount = await resetter.callCount
        XCTAssertEqual(currentCount, 1)
        await resetter.finish()
        try await first.value
        try await second.value
        let third = Task { try await service.resetPermissionDecisions() }
        await resetter.waitUntilStarted()
        let retryCount = await resetter.callCount
        XCTAssertEqual(retryCount, 2)
        await resetter.finish()
        try await third.value
    }

    func testUIShowsPendingStateRejectsDuplicateAndReturnsFailure() async {
        let resetter = SuspendedPermissionResetter()
        let model = PermissionResetActionModel()
        let first = Task { await model.reset { try await resetter.resetAllDecisions(for: "synthetic") } }
        await resetter.waitUntilStarted()
        XCTAssertTrue(model.isResetting)
        model.requestConfirmation()
        XCTAssertNil(model.alert)
        let second = Task { await model.reset { try await resetter.resetAllDecisions(for: "synthetic") } }
        for _ in 0..<100 { await Task.yield() }
        let currentCount = await resetter.callCount
        XCTAssertEqual(currentCount, 1)
        await resetter.finish(error: PermissionDecisionResetError.unavailable)
        await first.value
        await second.value
        XCTAssertFalse(model.isResetting)
        XCTAssertEqual(model.alert, .failure(PermissionDecisionResetError.unavailable.localizedDescription))
    }

    func testPermissionSummaryNeverAutomaticallyResetsDecisions() async {
        let resetter = SuspendedPermissionResetter()
        let service = PermissionService(checker: ResetPermissionChecker(), decisionResetter: resetter,
            bundleIdentifierProvider: { "local.synthetic.mactools" })
        for _ in 0..<5 { XCTAssertFalse(service.summary().canUseSuperRightClick) }
        let currentCount = await resetter.callCount
        XCTAssertEqual(currentCount, 0)
    }
}

private actor SuspendedPermissionResetter: PermissionDecisionResetting {
    private(set) var callCount = 0
    private var pending: [CheckedContinuation<Void, Error>] = []
    private var startWaiter: CheckedContinuation<Void, Never>?
    func resetAllDecisions(for bundleIdentifier: String) async throws {
        callCount += 1
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            startWaiter?.resume(); startWaiter = nil
        }
    }
    func waitUntilStarted() async {
        if !pending.isEmpty { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finish(error: Error? = nil) {
        let requests = pending; pending.removeAll()
        for request in requests {
            if let error { request.resume(throwing: error) } else { request.resume() }
        }
    }
}

private struct ResetPermissionChecker: PermissionChecking {
    func hasAccessibilityPermission() -> Bool { false }
    func hasInputMonitoringPermission() -> Bool { false }
    func hasPostEventPermission() -> Bool { false }
    func hasScreenRecordingPermission() -> Bool { false }
}
