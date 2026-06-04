import XCTest
@testable import MacToolsCore

final class ScaffoldTests: XCTestCase {
    func testLoggerCanRecordMessages() {
        let logger = Logger()
        logger.info("boot")

        XCTAssertEqual(logger.messages, ["INFO boot"])
    }
}
