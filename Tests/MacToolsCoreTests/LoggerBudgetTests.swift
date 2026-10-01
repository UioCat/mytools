import Foundation
import XCTest
@testable import MacToolsCore

final class LoggerBudgetTests: XCTestCase {
    func testDefaultMessageRetentionIsBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = Logger(debugLogDirectory: directory)
        defer { logger.flush(); try? FileManager.default.removeItem(at: directory) }
        for index in 0..<1_100 { logger.info("synthetic-\(index)") }
        XCTAssertLessThanOrEqual(logger.messages.count, 1_024)
        XCTAssertEqual(logger.messages.last, "INFO synthetic-1099")
    }
}

extension LoggerBudgetTests {
    func testPendingBudgetIncludesInFlightAndKeepsAcceptedOrder() throws {
        let entered = expectation(description: "writer entered")
        let release = DispatchSemaphore(value: 0)
        let writes = LoggerWrites()
        var limits = Logger.Limits()
        limits.pendingCount = 3
        limits.pendingBytes = 500
        let logger = Logger(debugLogDirectory: nil, limits: limits, write: { data in
            if writes.values.isEmpty { entered.fulfill(); release.wait() }
            writes.append(String(decoding: data, as: UTF8.self))
        })
        logger.info("synthetic-0")
        wait(for: [entered], timeout: 2)
        for index in 1..<5 { logger.info("synthetic-\(index)") }
        XCTAssertEqual(logger.pendingFileBudget.count, 3)
        XCTAssertLessThanOrEqual(logger.pendingFileBudget.bytes, 500)
        XCTAssertEqual(logger.droppedFileMessageCount, 2)
        release.signal()
        logger.flush()
        XCTAssertEqual(writes.values.map { $0.components(separatedBy: "INFO ").last! },
                       ["synthetic-0\n", "synthetic-1\n", "synthetic-2\n"])
        XCTAssertEqual(logger.pendingFileBudget.count, 0)
        XCTAssertEqual(logger.pendingFileBudget.bytes, 0)
    }

    func testLongLinesAndMessageBytesAreLimited() throws {
        var limits = Logger.Limits()
        limits.messageBytes = 128
        limits.lineBytes = 64
        let logger = Logger(debugLogDirectory: nil, limits: limits, write: { _ in })
        for _ in 0..<10 { logger.info(String(repeating: "合", count: 1_000)) }
        logger.flush()
        XCTAssertLessThanOrEqual(logger.messages.reduce(0) { $0 + $1.utf8.count }, 128)
        XCTAssertTrue(logger.messages.allSatisfy { $0.utf8.count <= 64 && $0.hasSuffix(" [truncated]") })
    }

    func testRotationLimitsDiskAndSecuresEveryFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var limits = Logger.Limits()
        limits.fileBytes = 128
        limits.archiveCount = 2
        limits.lineBytes = 64
        let logger = Logger(debugLogDirectory: directory, limits: limits)
        for index in 0..<30 { logger.info("synthetic-\(index)-" + String(repeating: "x", count: 30)) }
        logger.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertLessThanOrEqual(files.count, 3)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "debug.log" })
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertLessThanOrEqual((attributes[.size] as? NSNumber)?.intValue ?? .max, 128)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let current = try String(contentsOf: directory.appendingPathComponent("debug.log"), encoding: .utf8)
        XCTAssertTrue(current.contains("synthetic-29"))
    }
}

private final class LoggerWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var writes: [String] = []
    var values: [String] { lock.withLock { writes } }
    func append(_ value: String) { lock.withLock { writes.append(value) } }
}

extension LoggerBudgetTests {
    func testExistingOversizedLogsAreTrimmedAndPermissionsTightened() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        for name in ["debug.log", "debug.log.1", "debug.log.2"] {
            let file = directory.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data(repeating: 65, count: 4_096),
                                                         attributes: [.posixPermissions: 0o666]))
        }
        var limits = Logger.Limits()
        limits.fileBytes = 128
        limits.archiveCount = 2
        let logger = Logger(debugLogDirectory: directory, limits: limits)
        logger.info("synthetic-current")
        logger.flush()
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertLessThanOrEqual((attributes[.size] as? NSNumber)?.intValue ?? .max, 128)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
}
