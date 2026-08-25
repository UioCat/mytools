import Foundation
import XCTest

final class SuperRightClickMonitorSourceTests: XCTestCase {
    func testShortRightClickReplayContinuesAfterCurrentEventTap() throws {
        let source = try sourceFile("Sources/MacTools/Features/SuperRightClick/SuperRightClickMonitor.swift")

        XCTAssertTrue(
            source.contains("replaySystemRightClick(mouseUpEvent: event, proxy: proxy)")
        )
        XCTAssertTrue(
            source.contains("handleEvent(type: type, event: event, proxy: proxy)")
        )
        XCTAssertEqual(source.components(separatedBy: ".tapPostEvent(proxy)").count - 1, 2)
        XCTAssertFalse(source.contains(".post(tap: .cghidEventTap)"))
        XCTAssertFalse(source.contains("eventSourceUserData"))
    }

    func testTimerAndReleaseFallbackShareLongPressTriggerPath() throws {
        let source = try sourceFile("Sources/MacTools/Features/SuperRightClick/SuperRightClickMonitor.swift")

        XCTAssertEqual(
            source.components(separatedBy: "triggerSuperRightClick(if: route)").count - 1,
            2
        )
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
