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
            source.range(of: "syncCoordinator.bootstrapCredential")
        )
        let legacyLoad = try XCTUnwrap(
            source.range(
                of: "credentialAccess.load(",
                range: localLoad.upperBound..<source.endIndex
            )
        )

        XCTAssertLessThan(localLoad.lowerBound, cloudBootstrap.lowerBound)
        XCTAssertLessThan(cloudBootstrap.lowerBound, legacyLoad.lowerBound)
        XCTAssertFalse(source.contains("waiting for Keychain"))
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
