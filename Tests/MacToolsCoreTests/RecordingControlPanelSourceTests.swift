import Foundation
import XCTest

final class RecordingControlPanelSourceTests: XCTestCase {
    func testRecordingControlUsesSwiftUILiquidGlassAndRecordingIndicator() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "Sources/MacTools/Platform/ScreenCapture/RecordingControlPanelController.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("NSHostingView("))
        XCTAssertTrue(source.contains("RecordingControlView"))
        XCTAssertTrue(source.contains(".fill(MacToolsGlassTheme.recording)"))
        XCTAssertTrue(source.contains(".monospacedDigit()"))
        XCTAssertTrue(source.contains(".liquidGlassPanel("))
        XCTAssertFalse(source.contains("NSVisualEffectView"))
        XCTAssertFalse(source.contains("NSStackView"))
    }
}
