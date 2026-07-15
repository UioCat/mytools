import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenshotAnnotationTests: XCTestCase {
    func testAnnotationToolsIncludeEveryRestorableEditorChoice() {
        XCTAssertEqual(
            ScreenshotAnnotationTool.allCases,
            [.line, .freehand, .arrow, .rectangle, .mosaic]
        )
    }

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

    func testCommonAnnotationColorsUsePresetPaletteAndNormalizeLegacyCustomColor() {
        XCTAssertEqual(
            ScreenshotAnnotationColor.presets,
            [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
        )
        XCTAssertEqual(
            ScreenshotAnnotationColor(red: 0.6, green: 0.32, blue: 0.9).nearestPreset,
            .purple
        )
    }

    func testAnnotationStorePreservesFreehandPathColorAndLineWidth() {
        var store = ScreenshotAnnotationStore()
        let points = [
            CGPoint(x: 2, y: 3),
            CGPoint(x: 8, y: 7),
            CGPoint(x: 14, y: 4)
        ]
        let freehand = ScreenshotAnnotation.freehand(
            points: points,
            color: .red,
            lineWidth: 6
        )

        store.append(freehand)

        XCTAssertEqual(
            store.annotations,
            [.freehand(points: points, color: .red, lineWidth: 6)]
        )
    }

    func testFreehandStrokeCommitsClosedPathUsingAccumulatedLength() {
        var stroke = ScreenshotFreehandStroke()
        let points = [
            CGPoint(x: 2, y: 2),
            CGPoint(x: 12, y: 2),
            CGPoint(x: 12, y: 12),
            CGPoint(x: 2, y: 2)
        ]
        points.forEach { stroke.append($0) }

        XCTAssertEqual(stroke.points, points)
        XCTAssertEqual(
            stroke.annotation(color: .orange, lineWidth: 6),
            .freehand(points: points, color: .orange, lineWidth: 6)
        )
    }

    func testFreehandStrokeCanCommitFromLastInBoundsPointWhenReleaseIsOutside() {
        var stroke = ScreenshotFreehandStroke()
        stroke.append(CGPoint(x: 2, y: 2))
        stroke.append(CGPoint(x: 12, y: 2))

        XCTAssertNotNil(stroke.annotation(color: .blue, lineWidth: 3))
    }

    func testFreehandStrokeIgnoresNoiseAndRejectsTooShortPath() {
        var stroke = ScreenshotFreehandStroke()
        stroke.append(.zero)
        stroke.append(CGPoint(x: 0.5, y: 0))
        stroke.append(CGPoint(x: 1.5, y: 0))

        XCTAssertEqual(stroke.points, [.zero, CGPoint(x: 1.5, y: 0)])
        XCTAssertNil(stroke.annotation(color: .blue, lineWidth: 3))
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
