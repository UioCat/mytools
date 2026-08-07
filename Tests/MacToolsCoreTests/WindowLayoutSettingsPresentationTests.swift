import CoreGraphics
import XCTest
@testable import MacToolsCore

final class WindowLayoutSettingsPresentationTests: XCTestCase {
    func testPreviewGeometryFramesAndInsetsEveryTargetRegion() {
        let bounds = CGRect(x: 0, y: 0, width: 36, height: 24)

        XCTAssertEqual(
            WindowLayoutPreviewGeometry.screenFrame(in: bounds),
            CGRect(x: 1, y: 1, width: 34, height: 22)
        )
        XCTAssertEqual(
            WindowLayoutPreviewGeometry.targetFrame(for: WindowLayoutMode.leftHalf.previewSegment, in: bounds),
            CGRect(x: 3, y: 3, width: 15, height: 18)
        )
        XCTAssertEqual(
            WindowLayoutPreviewGeometry.targetFrame(for: WindowLayoutMode.rightThird.previewSegment, in: bounds),
            CGRect(x: 23, y: 3, width: 10, height: 18)
        )
        XCTAssertEqual(
            WindowLayoutPreviewGeometry.targetFrame(for: WindowLayoutMode.topHalf.previewSegment, in: bounds),
            CGRect(x: 3, y: 3, width: 30, height: 9)
        )
        XCTAssertEqual(
            WindowLayoutPreviewGeometry.targetFrame(for: WindowLayoutMode.bottomHalf.previewSegment, in: bounds),
            CGRect(x: 3, y: 12, width: 30, height: 9)
        )
        XCTAssertEqual(
            WindowLayoutPreviewGeometry.targetFrame(for: WindowLayoutMode.maximize.previewSegment, in: bounds),
            CGRect(x: 3, y: 3, width: 30, height: 18)
        )
    }

    func testMaximizedPreviewLeavesVisibleSpaceInsideScreenFrame() {
        let bounds = CGRect(x: 0, y: 0, width: 36, height: 24)
        let screen = WindowLayoutPreviewGeometry.screenFrame(in: bounds)
        let target = WindowLayoutPreviewGeometry.targetFrame(
            for: WindowLayoutMode.maximize.previewSegment,
            in: bounds
        )

        XCTAssertGreaterThan(target.minX, screen.minX)
        XCTAssertGreaterThan(target.minY, screen.minY)
        XCTAssertLessThan(target.maxX, screen.maxX)
        XCTAssertLessThan(target.maxY, screen.maxY)
    }

    @MainActor
    func testShortcutCaptureTextIsCenteredHorizontallyAndVertically() throws {
        let field = WindowLayoutShortcutCaptureTextField()
        let bounds = CGRect(x: 0, y: 0, width: 360, height: 32)
        let textRect = try XCTUnwrap(field.cell?.titleRect(forBounds: bounds))

        XCTAssertEqual(field.alignment, .center)
        XCTAssertLessThan(textRect.height, bounds.height)
        XCTAssertEqual(textRect.midY, bounds.midY, accuracy: 0.001)
    }
}
