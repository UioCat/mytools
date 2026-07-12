import Darwin
import Foundation
import XCTest
@testable import MacToolsCore

final class FinderCurrentFolderResolverTests: XCTestCase {
    func testFallsBackToScriptingDocumentWhenAccessibilityDocumentIsUnavailable() async {
        var authorizationCallCount = 0
        var scriptingCallCount = 0
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in .unavailable },
            automationAuthorization: {
                authorizationCallCount += 1
                return true
            },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Project/"
            }
        )

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Project")
        XCTAssertEqual(authorizationCallCount, 1)
        XCTAssertEqual(scriptingCallCount, 1)
    }

    func testValidAccessibilityDocumentWinsWithoutCallingScriptingDocument() async {
        var authorizationCallCount = 0
        var scriptingCallCount = 0
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in
                .value("file:///Users/example/Accessibility/" as CFString)
            },
            automationAuthorization: {
                authorizationCallCount += 1
                return true
            },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Scripting/"
            }
        )

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Accessibility")
        XCTAssertEqual(authorizationCallCount, 0)
        XCTAssertEqual(scriptingCallCount, 0)
    }

    func testNoFinderWindowReturnsDesktopWithoutCallingScriptingDocument() async {
        var authorizationCallCount = 0
        var scriptingCallCount = 0
        let desktopDirectory = URL(
            fileURLWithPath: "/Users/example/Desktop",
            isDirectory: true
        )
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: desktopDirectory,
            accessibilityDocument: { _ in .noWindow },
            automationAuthorization: {
                authorizationCallCount += 1
                return true
            },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Scripting/"
            }
        )

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result, desktopDirectory)
        XCTAssertEqual(authorizationCallCount, 0)
        XCTAssertEqual(scriptingCallCount, 0)
    }

    func testDeniedAutomationAuthorizationDoesNotLaunchScriptingQuery() async {
        var authorizationCallCount = 0
        var scriptingCallCount = 0
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in .unavailable },
            automationAuthorization: {
                authorizationCallCount += 1
                return false
            },
            scriptingDocument: {
                scriptingCallCount += 1
                return "file:///Users/example/Scripting/"
            }
        )

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertNil(result)
        XCTAssertEqual(authorizationCallCount, 1)
        XCTAssertEqual(scriptingCallCount, 0)
    }

    func testInvalidAccessibilityDocumentRequestsAuthorizationBeforeScriptingQuery() async {
        var callOrder: [String] = []
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in
                .value("https://example.com/not-a-folder" as CFString)
            },
            automationAuthorization: {
                callOrder.append("authorization")
                return true
            },
            scriptingDocument: {
                callOrder.append("query")
                return "file:///Users/example/Scripting/"
            }
        )

        let result = await resolver.currentFolderURL(processIdentifier: 42)

        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Scripting")
        XCTAssertEqual(callOrder, ["authorization", "query"])
    }

    @MainActor
    func testSuspendingScriptingDocumentAllowsMainActorToAdvance() async {
        let scriptingStarted = expectation(description: "scripting started")
        var releaseScripting: CheckedContinuation<Void, Never>?
        var mainActorAdvanced = false
        let resolver = SystemFinderCurrentFolderResolver(
            desktopDirectory: URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true),
            accessibilityDocument: { _ in .unavailable },
            automationAuthorization: { true },
            scriptingDocument: {
                scriptingStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseScripting = continuation
                }
                return "file:///Users/example/Project/"
            }
        )

        let resolution = Task { @MainActor in
            await resolver.currentFolderURL(processIdentifier: 42)
        }
        await fulfillment(of: [scriptingStarted], timeout: 1)

        await Task { @MainActor in
            mainActorAdvanced = true
        }.value

        XCTAssertTrue(mainActorAdvanced)
        releaseScripting?.resume()
        let result = await resolution.value
        XCTAssertEqual(result?.standardizedFileURL.path, "/Users/example/Project")
    }

    func testSuccessfulEmptyFinderWindowsIsNoWindow() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: 0),
            .noWindow
        )
    }

    func testCannotCompleteFinderWindowLookupIsUnavailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .cannotComplete, windowCount: 0),
            .unavailable
        )
    }

    func testAPIDisabledFinderWindowLookupIsUnavailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .apiDisabled, windowCount: 0),
            .unavailable
        )
    }

    func testSuccessfulPositiveFinderWindowCountIsAvailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: 1),
            .available
        )
    }

    func testMissingOrInconsistentFinderWindowCountIsUnavailable() {
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: nil),
            .unavailable
        )
        XCTAssertEqual(
            FinderWindowLookupClassification.classify(error: .success, windowCount: -1),
            .unavailable
        )
    }

    func testParsesPercentEncodedFinderDocumentURL() {
        let result = FinderDocumentURLParser.fileURL(
            from: "file:///Users/example/My%20Project/"
        )

        XCTAssertEqual(result?.path, "/Users/example/My Project")
        XCTAssertEqual(result?.isFileURL, true)
    }

    func testParsesAbsoluteFinderDocumentPath() {
        let result = FinderDocumentURLParser.fileURL(
            from: "/Users/example/Project"
        )

        XCTAssertEqual(result?.path, "/Users/example/Project")
        XCTAssertEqual(result?.isFileURL, true)
    }

    func testRejectsNonFileAndEmptyFinderDocumentValues() {
        XCTAssertNil(FinderDocumentURLParser.fileURL(from: "https://example.com"))
        XCTAssertNil(FinderDocumentURLParser.fileURL(from: "   "))
    }

    func testScriptingProcessRunnerReturnsValidatedOutput() async {
        let runner = FinderScriptingProcessRunner(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf file:///tmp/test/"],
            timeout: 1
        )

        let result = await runner.run()

        XCTAssertEqual(result, .success("file:///tmp/test/"))
    }

    func testScriptingProcessRunnerReportsNonzeroStatus() async {
        let runner = FinderScriptingProcessRunner(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 7"],
            timeout: 1
        )

        let result = await runner.run()

        XCTAssertEqual(result, .nonzeroStatus(7))
    }

    func testScriptingProcessRunnerReportsLaunchFailure() async {
        let runner = FinderScriptingProcessRunner(
            executableURL: URL(fileURLWithPath: "/path/that/does/not/exist"),
            arguments: [],
            timeout: 1
        )

        let result = await runner.run()

        XCTAssertEqual(result, .launchFailure)
    }

    func testScriptingProcessRunnerReportsInvalidOutput() async {
        let runner = FinderScriptingProcessRunner(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf not-a-file-url"],
            timeout: 1
        )

        let result = await runner.run()

        XCTAssertEqual(result, .invalidOutput)
    }

    func testTermIgnoringScriptingProcessTimesOutAfterReapingProcessTree() async throws {
        let pidFile = temporaryPIDFile()
        defer { cleanUpRecordedProcessesAndFile(at: pidFile) }
        let runner = termIgnoringRunner(pidFile: pidFile, timeout: 0.1)
        let startedAt = ContinuousClock.now

        let result = await runner.run()
        let elapsed = startedAt.duration(to: .now)
        let processIdentifiers = await recordedProcessIdentifiers(at: pidFile)

        XCTAssertEqual(result, .timeout)
        XCTAssertLessThan(elapsed, .seconds(1))
        XCTAssertEqual(processIdentifiers.count, 2)
        let didExit = await processesHaveExited(processIdentifiers)
        XCTAssertTrue(didExit)
    }

    func testCancellingScriptingProcessReturnsAfterReapingProcessTree() async throws {
        let pidFile = temporaryPIDFile()
        defer { cleanUpRecordedProcessesAndFile(at: pidFile) }
        let runner = termIgnoringRunner(pidFile: pidFile, timeout: 10)
        let task = Task {
            await runner.run()
        }
        let processIdentifiers = await recordedProcessIdentifiers(at: pidFile)
        XCTAssertEqual(processIdentifiers.count, 2)
        let cancelledAt = ContinuousClock.now

        task.cancel()
        let result = await task.value
        let elapsed = cancelledAt.duration(to: .now)

        XCTAssertEqual(result, .cancellation)
        XCTAssertLessThan(elapsed, .seconds(1))
        let didExit = await processesHaveExited(processIdentifiers)
        XCTAssertTrue(didExit)
    }

    private func termIgnoringRunner(
        pidFile: URL,
        timeout: TimeInterval
    ) -> FinderScriptingProcessRunner {
        let script = """
        trap '' TERM
        sleep 30 &
        child=$!
        printf '%s %s' "$$" "$child" > "$1"
        wait "$child"
        """
        return FinderScriptingProcessRunner(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script, "mactools-runner", pidFile.path],
            timeout: timeout,
            terminationGracePeriod: 0.2
        )
    }

    private func temporaryPIDFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mactools-runner-\(UUID().uuidString).pids")
    }

    private func recordedProcessIdentifiers(
        at url: URL,
        timeout: Duration = .seconds(1)
    ) async -> [pid_t] {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                let processIdentifiers = contents
                    .split(separator: " ")
                    .compactMap { pid_t($0) }
                if processIdentifiers.count == 2 {
                    return processIdentifiers
                }
            }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return []
    }

    private func processesHaveExited(
        _ processIdentifiers: [pid_t],
        timeout: Duration = .seconds(1)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        repeat {
            if processIdentifiers.allSatisfy({ Darwin.kill($0, 0) == -1 && errno == ESRCH }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        return false
    }

    private func cleanUpRecordedProcessesAndFile(at url: URL) {
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            for processIdentifier in contents.split(separator: " ").compactMap({ pid_t($0) }) {
                _ = Darwin.kill(processIdentifier, SIGKILL)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}
