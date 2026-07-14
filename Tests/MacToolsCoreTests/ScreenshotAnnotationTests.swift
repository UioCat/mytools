import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenshotAnnotationTests: XCTestCase {
    func testAnnotationLineWidthProvidesCommonChoices() {
        XCTAssertEqual(ScreenshotAnnotationLineWidth.allCases, [.thin, .medium, .thick])
        XCTAssertEqual(ScreenshotAnnotationLineWidth.thin.points, 2)
        XCTAssertEqual(ScreenshotAnnotationLineWidth.medium.points, 3)
        XCTAssertEqual(ScreenshotAnnotationLineWidth.thick.points, 6)
    }

    func testArrowHeadLengthScalesWithSelectedLineWidth() {
        XCTAssertEqual(ScreenshotAnnotationArrowStyle.headLength(forLineWidth: 3), 10, accuracy: 0.001)
        XCTAssertEqual(ScreenshotAnnotationArrowStyle.headLength(forLineWidth: 6), 20, accuracy: 0.001)
    }

    func testAnnotationPreservesSelectedLineWidth() {
        let line = ScreenshotAnnotation.line(
            start: .zero,
            end: CGPoint(x: 20, y: 20),
            color: .red,
            lineWidth: 12
        )

        XCTAssertEqual(
            line,
            .line(start: .zero, end: CGPoint(x: 20, y: 20), color: .red, lineWidth: 12)
        )
    }

    func testCommittedMosaicDoesNotShowDragBoundary() {
        XCTAssertTrue(ScreenshotMosaicOutlinePolicy.shouldShowOutline(isPreview: true))
        XCTAssertFalse(ScreenshotMosaicOutlinePolicy.shouldShowOutline(isPreview: false))
    }

    func testCommonAnnotationColorsIncludeCustomizableScreenshotPalette() {
        XCTAssertEqual(
            ScreenshotAnnotationColor.presets,
            [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
        )
        XCTAssertEqual(
            ScreenshotAnnotationColor(red: 0.2, green: 0.4, blue: 0.6),
            .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        )
    }

    func testAnnotationStorePreservesCircleAndSelectedColor() {
        var store = ScreenshotAnnotationStore()
        let circle = ScreenshotAnnotation.circle(
            from: CGPoint(x: 22, y: 15),
            to: CGPoint(x: 2, y: 3),
            color: .red
        )

        store.append(circle)

        XCTAssertEqual(
            store.annotations,
            [.circle(CGRect(x: 10, y: 3, width: 12, height: 12), color: .red)]
        )
    }

    func testAnnotationStoreUndoesLatestMosaicOnly() {
        var store = ScreenshotAnnotationStore()
        let arrow = ScreenshotAnnotation.arrow(start: .zero, end: CGPoint(x: 10, y: 10))
        let mosaic = ScreenshotAnnotation.mosaic(CGRect(x: 1, y: 1, width: 8, height: 8))
        store.append(arrow)
        store.append(mosaic)

        XCTAssertEqual(store.undo(), mosaic)
        XCTAssertEqual(store.annotations, [arrow])
    }
}
