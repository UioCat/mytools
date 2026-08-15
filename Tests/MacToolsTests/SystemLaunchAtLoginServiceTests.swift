import ServiceManagement
import XCTest
@testable import MacTools
@testable import MacToolsCore

final class SystemLaunchAtLoginServiceTests: XCTestCase {
    @MainActor
    func testInitialStateMapsEveryKnownSystemStatus() {
        let cases: [(SMAppService.Status, LaunchAtLoginSettingsState)] = [
            (.notRegistered, .disabled),
            (.enabled, .enabled),
            (.requiresApproval, .requiresApproval),
            (.notFound, .unavailable),
        ]

        for (status, expectedState) in cases {
            let service = makeService(backend: FakeLaunchAtLoginBackend(status: status))
            XCTAssertEqual(service.state, expectedState, "Unexpected mapping for \(status)")
        }
    }

    @MainActor
    func testInitialStateAndRefreshFollowSystemStatus() {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        let service = makeService(backend: backend)

        XCTAssertEqual(service.state, .disabled)
        backend.status = .enabled
        service.refresh()
        XCTAssertEqual(service.state, .enabled)
    }

    @MainActor
    func testEnableAndDisableExecuteOnlyRequiredSystemAction() {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        let service = makeService(backend: backend)

        backend.statusAfterRegister = .enabled
        service.setEnabled(true)
        XCTAssertEqual(backend.registerCallCount, 1)
        XCTAssertEqual(service.state, .enabled)

        service.setEnabled(true)
        XCTAssertEqual(backend.registerCallCount, 1)

        backend.statusAfterUnregister = .notRegistered
        service.setEnabled(false)
        XCTAssertEqual(backend.unregisterCallCount, 1)
        XCTAssertEqual(service.state, .disabled)

        service.setEnabled(false)
        XCTAssertEqual(backend.unregisterCallCount, 1)
    }

    @MainActor
    func testEnableFailureThatRequiresApprovalOffersApprovalAction() {
        let backend = FakeLaunchAtLoginBackend(status: .notRegistered)
        backend.statusAfterRegister = .requiresApproval
        backend.registerError = TestError.operationFailed
        let service = makeService(backend: backend)

        service.setEnabled(true)

        XCTAssertEqual(service.state, .requiresApproval)
    }

    @MainActor
    func testEnablingWhileApprovalIsRequiredDoesNotRegisterAgain() {
        let backend = FakeLaunchAtLoginBackend(status: .requiresApproval)
        let service = makeService(backend: backend)

        service.setEnabled(true)

        XCTAssertEqual(service.state, .requiresApproval)
        XCTAssertEqual(backend.registerCallCount, 0)
    }

    @MainActor
    func testDisableFailureWhileApprovalIsRequiredKeepsFailureDirection() {
        let backend = FakeLaunchAtLoginBackend(status: .requiresApproval)
        backend.statusAfterUnregister = .requiresApproval
        backend.unregisterError = TestError.operationFailed
        let service = makeService(backend: backend)

        service.setEnabled(false)

        guard case let .failed(isEnabled, message) = service.state else {
            return XCTFail("Expected a failed state")
        }
        XCTAssertTrue(isEnabled)
        XCTAssertTrue(message.hasPrefix("关闭失败："))
        XCTAssertFalse(service.state.requiresSystemApproval)
    }

    @MainActor
    func testThrownActionUsesSuccessfulFinalSystemState() {
        let enableBackend = FakeLaunchAtLoginBackend(status: .notRegistered)
        enableBackend.statusAfterRegister = .enabled
        enableBackend.registerError = TestError.operationFailed
        let enableService = makeService(backend: enableBackend)

        enableService.setEnabled(true)
        XCTAssertEqual(enableService.state, .enabled)

        let disableBackend = FakeLaunchAtLoginBackend(status: .enabled)
        disableBackend.statusAfterUnregister = .notRegistered
        disableBackend.unregisterError = TestError.operationFailed
        let disableService = makeService(backend: disableBackend)

        disableService.setEnabled(false)
        XCTAssertEqual(disableService.state, .disabled)
    }

    @MainActor
    func testUnavailableStatusDoesNotExecuteActions() {
        let backend = FakeLaunchAtLoginBackend(status: .notFound)
        let service = makeService(backend: backend)

        service.setEnabled(true)
        service.setEnabled(false)

        XCTAssertEqual(service.state, .unavailable)
        XCTAssertEqual(backend.registerCallCount, 0)
        XCTAssertEqual(backend.unregisterCallCount, 0)
    }

    @MainActor
    func testSystemSettingsActionRemainsInjected() {
        let backend = FakeLaunchAtLoginBackend(status: .requiresApproval)
        let service = makeService(backend: backend)

        service.openSystemSettings()

        XCTAssertEqual(backend.openSystemSettingsCallCount, 1)
    }

    @MainActor
    private func makeService(
        backend: FakeLaunchAtLoginBackend
    ) -> SystemLaunchAtLoginService {
        SystemLaunchAtLoginService(
            statusProvider: { backend.status },
            registerAction: { try backend.register() },
            unregisterAction: { try backend.unregister() },
            openSystemSettingsAction: { backend.openSystemSettings() }
        )
    }
}

private enum TestError: Error {
    case operationFailed
}

@MainActor
private final class FakeLaunchAtLoginBackend {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status?
    var statusAfterUnregister: SMAppService.Status?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let statusAfterRegister { status = statusAfterRegister }
        if let registerError { throw registerError }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let statusAfterUnregister { status = statusAfterUnregister }
        if let unregisterError { throw unregisterError }
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}
