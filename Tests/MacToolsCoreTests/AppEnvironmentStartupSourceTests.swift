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
        let source = try sourceFile("Sources/MacTools/App/AppEnvironment.swift")
        let workerStart = try XCTUnwrap(source.range(of: "private actor AppMaintenanceWorker"))
        let environmentStart = try XCTUnwrap(source.range(of: "@MainActor\nfinal class AppEnvironment"))
        let worker = source[workerStart.lowerBound..<environmentStart.lowerBound]

        XCTAssertTrue(worker.contains("guard !hasRun else { return }"))
        let staging = try XCTUnwrap(worker.range(of: "removeStagingFiles"))
        let reconciliation = try XCTUnwrap(worker.range(of: "reconcilePayloadStorage"))
        let evictionCleanup = try XCTUnwrap(worker.range(of: "cleanupOrphanedLocalEvictions"))
        XCTAssertLessThan(staging.lowerBound, reconciliation.lowerBound)
        XCTAssertLessThan(reconciliation.lowerBound, evictionCleanup.lowerBound)
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
