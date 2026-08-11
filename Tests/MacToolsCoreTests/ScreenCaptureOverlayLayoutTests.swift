import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import MacToolsCore

final class ScreenCaptureOverlayLayoutTests: XCTestCase {
    func testDefaultCaptureModeIsScreenshot() {
        XCTAssertEqual(ScreenCaptureMode.default, .screenshot)
    }

    func testModeToolbarIsPinnedToTopCenterOfDisplay() {
        let frame = ScreenCaptureOverlayLayout.modeToolbarFrame(
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 622, y: 840, width: 196, height: 44))
    }

    func testEditorToolbarPrefersBelowSelectionAndStaysInsideDisplay() {
        let frame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: CGRect(x: 120, y: 240, width: 700, height: 400),
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 100, y: 160, width: 720, height: 68))
    }

    func testEditorToolbarMovesAboveLowSelectionAndClampsHorizontally() {
        let frame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: CGRect(x: 1_298, y: 8, width: 140, height: 120),
            displayBounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 708, y: 140, width: 720, height: 68))
    }

    func testEditorToolbarShrinksToStayInsideANarrowDisplay() {
        let frame = ScreenCaptureOverlayLayout.editorToolbarFrame(
            selectionFrame: CGRect(x: 40, y: 100, width: 300, height: 240),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 700)
        )

        XCTAssertEqual(frame, CGRect(x: 12, y: 20, width: 476, height: 68))
    }

    func testCompactEditorToolbarControlsFitWithinNarrowDisplayWidth() {
        XCTAssertEqual(ScreenCaptureEditorToolbarMetrics.compactBreakpoint, 720)
        XCTAssertEqual(ScreenCaptureEditorToolbarMetrics.ultraCompactBreakpoint, 476)
        XCTAssertEqual(
            ScreenCaptureEditorToolbarMetrics.contentWidth(controlCount: 11),
            468
        )
        XCTAssertLessThanOrEqual(
            ScreenCaptureEditorToolbarMetrics.contentWidth(controlCount: 11),
            ScreenCaptureEditorToolbarMetrics.ultraCompactBreakpoint
        )
    }

    @MainActor
    func testCompactToolbarRendersActualEditorControlsWithoutClipping() throws {
        let measurement = ScreenshotCompactToolbarMeasurementSink()
        let editor = ScreenshotEditorView(
            image: try makeSolidImage(width: 400, height: 300),
            imageFrame: CGRect(x: 200, y: 120, width: 400, height: 300),
            toolbarFrame: CGRect(x: 162, y: 450, width: 476, height: 68),
            settings: .defaults,
            onSettingsChange: { _ in true },
            onCopy: { _ in },
            onCancel: {},
            registerEscapeHandler: { _ in },
            clearEscapeHandler: {}
        )
        .environment(\.screenshotCompactToolbarMeasurement, measurement)
        .frame(width: 800, height: 600)
        let hostingView = NSHostingView(rootView: editor)
        hostingView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)

        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(
            Set(measurement.frames.keys),
            Set(
                ScreenshotAnnotationTool.allCases.map { "tool-\($0.rawValue)" }
                    + ["undo", "style", "cancel", "done"]
            )
        )
        let frames = measurement.frames.values.sorted { $0.minX < $1.minX }
        XCTAssertEqual(frames.count, 11)
        for frame in frames {
            XCTAssertEqual(frame.width, 40, accuracy: 0.01)
            XCTAssertEqual(frame.height, 40, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, 476)
        }
        for (leading, trailing) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(trailing.minX - leading.maxX, 2, accuracy: 0.01)
        }
    }

    func testRecordingControlIsPinnedToTopCenterOfSelectedDisplay() {
        let frame = ScreenCaptureOverlayLayout.recordingControlFrame(
            visibleFrame: CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: -808, y: 836, width: 176, height: 48))
    }

    func testRecordingControlStaysBelowMenuBarAndCentersInVisibleFrame() {
        let frame = ScreenCaptureOverlayLayout.recordingControlFrame(
            visibleFrame: CGRect(x: 80, y: 40, width: 1_360, height: 836)
        )

        XCTAssertEqual(frame, CGRect(x: 672, y: 812, width: 176, height: 48))
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}
