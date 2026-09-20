import CoreGraphics
import XCTest
@testable import MacTools

final class RightClickEventProcessorTests: XCTestCase {
    func testQuickRightDragHandsCompleteGestureBackToSystem() throws {
        let fixture = Fixture()
        _ = try fixture.send(.rightMouseDown, at: 1_000)
        XCTAssertTrue(try fixture.send(.rightMouseDragged, at: 1_050, location: CGPoint(x: 70, y: 60)))
        XCTAssertEqual(fixture.replayed.map(\.type), [.rightMouseDown, .rightMouseDragged])
        XCTAssertFalse(try fixture.send(.rightMouseDragged, at: 1_100, location: CGPoint(x: 90, y: 60)))
        fixture.now = 2_000
        fixture.processor.timerFired()
        XCTAssertFalse(try fixture.send(.rightMouseUp, at: 2_010))
        XCTAssertEqual(fixture.triggers, 0)
    }

    func testShortClickReplaysOriginalPairOnceWithOriginalMetadata() throws {
        for threshold in [250, 300, 350] {
            let fixture = Fixture(threshold: threshold)
            XCTAssertTrue(try fixture.send(.rightMouseDown, at: 1_000))
            XCTAssertTrue(try fixture.send(.rightMouseUp, at: 1_000 + threshold - 1))
            fixture.now = 5_000
            fixture.processor.timerFired()
            XCTAssertEqual(fixture.replayed.map(\.type), [.rightMouseDown, .rightMouseUp])
            XCTAssertEqual(fixture.replayed.first?.timestamp, 1_000_000_000)
            XCTAssertEqual(fixture.replayed.first?.location, CGPoint(x: 40, y: 60))
            XCTAssertEqual(fixture.replayed.first?.flags, .maskShift)
            XCTAssertEqual(fixture.triggers, 0)
            XCTAssertNil(fixture.processor.deadlineMilliseconds)
        }
    }

    func testLongPressConsumesDownDragsDuplicateDownAndUpWithoutSystemReplay() throws {
        for threshold in [250, 300, 350] {
            let fixture = Fixture(threshold: threshold)
            XCTAssertTrue(try fixture.send(.rightMouseDown, at: 1_000))
            XCTAssertTrue(try fixture.send(.rightMouseDragged, at: 1_100))
            fixture.now = 1_000 + threshold
            fixture.processor.timerFired()
            XCTAssertTrue(try fixture.send(.rightMouseDown, at: fixture.now + 1))
            XCTAssertTrue(try fixture.send(.rightMouseDragged, at: fixture.now + 2))
            XCTAssertTrue(try fixture.send(.rightMouseUp, at: fixture.now + 20))
            fixture.processor.timerFired()
            XCTAssertEqual(fixture.beginnings, 1)
            XCTAssertEqual(fixture.triggers, 1)
            XCTAssertTrue(fixture.replayed.isEmpty)
        }
    }

    func testDelayedDeliveryUsesEventTimeAndReleaseTriggersBeforeTimer() throws {
        let fixture = Fixture()
        fixture.now = 9_000
        _ = try fixture.send(.rightMouseDown, at: 1_000)
        _ = try fixture.send(.rightMouseUp, at: 1_250)
        fixture.processor.timerFired()
        XCTAssertEqual(fixture.triggers, 1)
        XCTAssertTrue(fixture.replayed.isEmpty)
    }

    func testInterruptedGestureCannotTriggerAndOrphanEventsPassUntilNextDown() throws {
        let fixture = Fixture()
        _ = try fixture.send(.rightMouseDown, at: 1_000)
        fixture.processor.cancel()
        fixture.now = 2_000
        fixture.processor.timerFired()
        XCTAssertFalse(try fixture.send(.rightMouseDragged, at: 2_001))
        XCTAssertFalse(try fixture.send(.rightMouseUp, at: 2_002))
        XCTAssertEqual(fixture.triggers, 0)
        XCTAssertTrue(fixture.replayed.isEmpty)
        _ = try fixture.send(.rightMouseDown, at: 3_000)
        _ = try fixture.send(.rightMouseUp, at: 3_050)
        XCTAssertEqual(fixture.replayed.count, 2)
    }

    func testZeroTimestampFallsBackToMonotonicClockAndThousandsOfGesturesDoNotLeakState() throws {
        let fixture = Fixture()
        for index in 0..<2_000 {
            fixture.now = 1_000 + index * 1_000
            _ = try fixture.send(.rightMouseDown, at: 0)
            fixture.now += index.isMultiple(of: 2) ? 50 : 300
            _ = try fixture.send(.rightMouseUp, at: 0)
        }
        XCTAssertEqual(fixture.triggers, 1_000)
        XCTAssertEqual(fixture.replayed.count, 2_000)
    }
}

private final class Fixture {
    var now = 1_000
    var triggers = 0
    var beginnings = 0
    var replayed: [CGEvent] = []
    let threshold: Int
    lazy var processor = RightClickEventProcessor(thresholdMilliseconds: threshold, uptime: { [unowned self] in now }) { [unowned self] output in
        if case .triggered = output { triggers += 1 }
        if case .began = output { beginnings += 1 }
    }
    init(threshold: Int = 250) { self.threshold = threshold }
    func send(_ type: CGEventType, at milliseconds: Int, location: CGPoint = CGPoint(x: 40, y: 60)) throws -> Bool {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type,
                                         mouseCursorPosition: location, mouseButton: .right))
        event.timestamp = UInt64(milliseconds) * 1_000_000
        event.flags = .maskShift
        return processor.process(type: type, event: event) { replayed.append($0) }
    }
}
