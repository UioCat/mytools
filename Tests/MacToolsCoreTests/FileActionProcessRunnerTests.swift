import Foundation
import XCTest
@testable import MacToolsCore

final class FileActionProcessRunnerTests: XCTestCase {
    func testNonzeroExitBecomesControlledFailureWithoutScriptPath() async throws {
        do {
            try await Task.detached {
                try SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), arguments: [
                    "-c", "printf 'synthetic-private-path\\n'; printf 'synthetic-private-path\\n' >&2; exit 7"
                ])
            }.value
            XCTFail("A nonzero command exit must be reported to the visible action state")
        } catch {
            XCTAssertEqual(error as? FileActionProcessError, .commandFailed(exitCode: 7))
            XCTAssertFalse(String(describing: error).contains("synthetic-private-path"))
        }
    }

    func testSuccessfulExitWithLargeOutputCompletesWithoutPipeDeadlock() async throws {
        let script = try makeScript("i=0\nwhile [ $i -lt 20000 ]; do printf 'synthetic output line\\n'; printf 'synthetic output line\\n' >&2; i=$((i + 1)); done\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        try await Task.detached { try SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), arguments: [script.path]) }.value
    }

    private func makeScript(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("synthetic-command.sh")
        try contents.write(to: script, atomically: true, encoding: .utf8)
        return script
    }
}
