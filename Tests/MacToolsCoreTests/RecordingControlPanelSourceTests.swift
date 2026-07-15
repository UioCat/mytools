import Foundation
import XCTest

final class RecordingControlPanelSourceTests: XCTestCase {
    func testRecordingControlDoesNotRenderLeadingRedIndicator() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/MacTools/App/ScreenCapture/RecordingControlPanelController.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("let indicator = NSView"))
        XCTAssertFalse(source.contains("indicator.layer?.backgroundColor"))
        XCTAssertTrue(source.contains("NSStackView(views: [title, elapsedLabel, stopButton])"))
    }
}
