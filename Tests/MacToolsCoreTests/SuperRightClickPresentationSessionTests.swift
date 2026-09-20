import XCTest
@testable import MacToolsCore

final class SuperRightClickPresentationSessionTests: XCTestCase {
    func testDelayedTriggerAndOlderClicksCannotDismissNewPanel() {
        var session = SuperRightClickPresentationSession()
        session.begin(id: UUID(), at: 10)
        XCTAssertFalse(session.acceptsDismissal(at: 9.9))
        XCTAssertFalse(session.acceptsDismissal(at: 10))
        XCTAssertFalse(session.acceptsDismissal(at: 10.0009))
        XCTAssertTrue(session.acceptsDismissal(at: 10.002))
    }

    func testClosedAndReplacedSessionsRejectLateTranslationOrFinderResults() {
        var session = SuperRightClickPresentationSession()
        let old = UUID(), current = UUID()
        session.begin(id: old, at: 1)
        XCTAssertTrue(session.accepts(old))
        session.begin(id: current, at: 2)
        XCTAssertFalse(session.accepts(old))
        XCTAssertTrue(session.accepts(current))
        session.dismiss()
        XCTAssertFalse(session.accepts(current))
        XCTAssertFalse(session.acceptsDismissal(at: 3))
    }
}
