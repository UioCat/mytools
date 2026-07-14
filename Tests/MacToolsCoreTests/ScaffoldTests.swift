import XCTest
@testable import MacToolsCore

final class ScaffoldTests: XCTestCase {
    func testLoggerRecordsMessagesInOwnerOnlyStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoggerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = Logger(debugLogDirectory: directory)

        logger.info("boot")

        XCTAssertEqual(logger.messages, ["INFO boot"])
        XCTAssertEqual(try permissions(at: directory), 0o700)
        XCTAssertEqual(try permissions(at: directory.appendingPathComponent("debug.log")), 0o600)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}
