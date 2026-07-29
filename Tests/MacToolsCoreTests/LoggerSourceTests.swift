import Foundation
import XCTest

final class LoggerSourceTests: XCTestCase {
    func testCallerPathQueuesFileIOAndApplicationFlushesOnTermination() throws {
        let loggerSource = try sourceFile("Sources/MacToolsCore/Utilities/Logger.swift")
        let recordStart = try XCTUnwrap(loggerSource.range(of: "private func record"))
        let writerStart = try XCTUnwrap(
            loggerSource.range(of: "private static func writeToDebugLog")
        )
        let recordBody = loggerSource[recordStart.lowerBound..<writerStart.lowerBound]

        XCTAssertTrue(recordBody.contains("Self.fileWriteQueue.async"))
        XCTAssertFalse(recordBody.contains("FileHandle"))

        let appDelegateSource = try sourceFile("Sources/MacTools/Application/AppDelegate.swift")
        XCTAssertTrue(appDelegateSource.contains("func applicationWillTerminate"))
        XCTAssertTrue(appDelegateSource.contains("environment.logger.flush()"))
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
