import Foundation
import XCTest

final class AppEnvironmentStartupSourceTests: XCTestCase {
    func testPayloadMaintenanceRunsAfterRuntimeServicesStartInsteadOfDuringInitialization() throws {
        let source = try sourceFile("Sources/MacTools/App/AppEnvironment.swift")
        let initializerStart = try XCTUnwrap(source.range(of: "    init() {"))
        let startMethod = try XCTUnwrap(
            source.range(of: "    func start() {", range: initializerStart.upperBound..<source.endIndex)
        )
        let initializer = source[initializerStart.lowerBound..<startMethod.lowerBound]

        XCTAssertFalse(initializer.contains("removeStagingFiles"))
        XCTAssertFalse(initializer.contains("reconcilePayloadStorage"))
        XCTAssertFalse(initializer.contains("cleanupOrphanedLocalEvictions"))

        let startBody = source[startMethod.lowerBound...]
        XCTAssertTrue(startBody.contains("startClipboardPolling()"))
        XCTAssertTrue(startBody.contains("startSuperRightClickMonitor()"))
        XCTAssertTrue(startBody.contains("await maintenanceWorker.run()"))
    }

    func testMaintenanceWorkerPreservesCleanupOrderAndSingleRunGuard() throws {
        let source = try sourceFile("Sources/MacTools/App/AppEnvironmentWorkers.swift")
        let workerStart = try XCTUnwrap(source.range(of: "actor AppMaintenanceWorker"))
        let pasteAttemptStart = try XCTUnwrap(
            source.range(of: "@MainActor\nfinal class PasteActivationAttempt")
        )
        let worker = source[workerStart.lowerBound..<pasteAttemptStart.lowerBound]

        XCTAssertTrue(worker.contains("guard !hasRun else { return }"))
        let staging = try XCTUnwrap(worker.range(of: "removeStagingFiles"))
        let reconciliation = try XCTUnwrap(worker.range(of: "reconcilePayloadStorage"))
        let evictionCleanup = try XCTUnwrap(worker.range(of: "cleanupOrphanedLocalEvictions"))
        XCTAssertLessThan(staging.lowerBound, reconciliation.lowerBound)
        XCTAssertLessThan(reconciliation.lowerBound, evictionCleanup.lowerBound)
    }

    func testAutomaticPasteKeepsActivationAndTimeoutPathsWithoutDeprecatedOption() throws {
        let source = try sourceFile("Sources/MacTools/App/AppEnvironmentWorkers.swift")

        XCTAssertTrue(source.contains("final class PasteActivationAttempt"))
        XCTAssertTrue(source.contains("milliseconds(80)"))
        XCTAssertTrue(source.contains("milliseconds(800)"))
        XCTAssertTrue(source.contains("targetApplication.activate(options: [.activateAllWindows])"))
        XCTAssertFalse(source.contains("activateIgnoringOtherApps"))
    }

    func testCredentialStartupChecksLocalAndCloudBeforeLegacyMigration() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/AppEnvironment+Credentials.swift"
        )

        let localLoad = try XCTUnwrap(
            source.range(of: "credentialAccess.loadLocal")
        )
        let cloudBootstrap = try XCTUnwrap(
            source.range(of: "syncCoordinator.bootstrapCredentialAndSync")
        )
        let legacyLoad = try XCTUnwrap(
            source.range(
                of: "credentialAccess.load(",
                range: localLoad.upperBound..<source.endIndex
            )
        )

        XCTAssertLessThan(localLoad.lowerBound, cloudBootstrap.lowerBound)
        XCTAssertLessThan(cloudBootstrap.lowerBound, legacyLoad.lowerBound)
        XCTAssertFalse(source.contains("syncCoordinator.bootstrapCredential()"))
        XCTAssertFalse(source.contains("waiting for Keychain"))
    }

    func testSyncFolderPreparationRunsThroughBackgroundWorker() throws {
        let environmentSource = try sourceFile("Sources/MacTools/App/AppEnvironment.swift")
        let workersSource = try sourceFile("Sources/MacTools/App/AppEnvironmentWorkers.swift")

        XCTAssertTrue(environmentSource.contains("await worker.prepare("))
        XCTAssertTrue(environmentSource.contains("await worker.persist(prepared)"))
        XCTAssertTrue(environmentSource.contains("syncFolderSelectionGeneration"))
        XCTAssertFalse(
            environmentSource.contains(
                "_ = try DriveSyncStore(rootURL: rootURL).prepare("
            )
        )
        XCTAssertTrue(workersSource.contains("final class SyncFolderPreparationWorker"))
        XCTAssertTrue(workersSource.contains("qos: .utility"))
    }

    func testRemoteSettingsRestartSuperRightClickMonitorOnlyWhenItsDependenciesChange() throws {
        let source = try sourceFile("Sources/MacTools/App/AppEnvironment.swift")
        let applyStart = try XCTUnwrap(
            source.range(of: "    private func applyRemoteSettings(_ remoteSettings: AppSettings) {")
        )
        let scheduleStart = try XCTUnwrap(
            source.range(
                of: "    func scheduleSync() {",
                range: applyStart.upperBound..<source.endIndex
            )
        )
        let applyBody = source[applyStart.lowerBound..<scheduleStart.lowerBound]

        let restartDecision = try XCTUnwrap(
            applyBody.range(of: "let shouldRestartSuperRightClickMonitor =")
        )
        let superRightClickComparison = try XCTUnwrap(
            applyBody.range(of: "merged.superRightClick != settings.superRightClick")
        )
        let translationComparison = try XCTUnwrap(
            applyBody.range(of: "merged.translation != settings.translation")
        )
        let assignment = try XCTUnwrap(applyBody.range(of: "settings = merged"))
        XCTAssertLessThan(restartDecision.lowerBound, superRightClickComparison.lowerBound)
        XCTAssertLessThan(superRightClickComparison.lowerBound, translationComparison.lowerBound)
        XCTAssertLessThan(translationComparison.lowerBound, assignment.lowerBound)
        XCTAssertTrue(
            applyBody.contains(
                """
                if shouldRestartSuperRightClickMonitor {
                                startSuperRightClickMonitor()
                            }
                """
            )
        )
    }

    func testCredentialApplyRefreshesRuntimeOnlyWhenLoadedValueChanges() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/AppEnvironment+Credentials.swift"
        )
        let applyStart = try XCTUnwrap(
            source.range(of: "    func applyCredentialLoadResult(")
        )
        let redactionStart = try XCTUnwrap(
            source.range(
                of: "    func redactLegacyCredential(at url: URL) {",
                range: applyStart.upperBound..<source.endIndex
            )
        )
        let applyBody = source[applyStart.lowerBound..<redactionStart.lowerBound]

        let decision = try XCTUnwrap(
            applyBody.range(of: "CredentialRuntimeUpdatePolicy.decision(")
        )
        let settingsAssignment = try XCTUnwrap(
            applyBody.range(of: "settings.translation.apiKey = result.value")
        )
        let publishedValueGuard = try XCTUnwrap(
            applyBody.range(of: "if decision.shouldUpdatePublishedValue {")
        )
        let unavailableGuard = try XCTUnwrap(
            applyBody.range(of: "if decision.shouldClearUnavailableState {")
        )
        let serviceRefreshGuard = try XCTUnwrap(
            applyBody.range(
                of: "guard decision.shouldRefreshDependentServices else { return }"
            )
        )
        let settingsNotification = try XCTUnwrap(
            applyBody.range(of: "onSettingsChanged(settings)")
        )
        let monitorRestart = try XCTUnwrap(
            applyBody.range(of: "startSuperRightClickMonitor()")
        )

        XCTAssertLessThan(decision.lowerBound, settingsAssignment.lowerBound)
        XCTAssertLessThan(publishedValueGuard.lowerBound, serviceRefreshGuard.lowerBound)
        XCTAssertLessThan(unavailableGuard.lowerBound, serviceRefreshGuard.lowerBound)
        XCTAssertLessThan(serviceRefreshGuard.lowerBound, settingsNotification.lowerBound)
        XCTAssertLessThan(serviceRefreshGuard.lowerBound, monitorRestart.lowerBound)
    }

    func testLegacyKeychainReaderIsReadOnly() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/Sync/KeychainCredentialStore.swift"
        )

        XCTAssertTrue(source.contains("SecItemCopyMatching"))
        XCTAssertFalse(source.contains("SecItemAdd"))
        XCTAssertFalse(source.contains("SecItemUpdate"))
        XCTAssertFalse(source.contains("SecItemDelete"))
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
