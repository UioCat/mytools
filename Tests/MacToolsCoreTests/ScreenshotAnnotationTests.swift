import CoreGraphics
import XCTest
@testable import MacToolsCore

final class ScreenshotAnnotationTests: XCTestCase {
    func testAnnotationToolsIncludeEveryRestorableEditorChoice() {
        XCTAssertEqual(
            ScreenshotAnnotationTool.allCases,
            [.line, .freehand, .arrow, .rectangle, .mosaic, .text, .label]
        )
    }

    func testAnnotationFontSizeProvidesThreeReadableChoices() {
        XCTAssertEqual(ScreenshotAnnotationFontSize.allCases, [.small, .medium, .large])
        XCTAssertEqual(ScreenshotAnnotationFontSize.small.points, 12)
        XCTAssertEqual(ScreenshotAnnotationFontSize.medium.points, 16)
        XCTAssertEqual(ScreenshotAnnotationFontSize.large.points, 24)
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

    func testAnnotationStoreKeepsStableIdentityAcrossUpdateAndMove() throws {
        var store = ScreenshotAnnotationStore()
        let original = ScreenshotAnnotation.text(
            text: "第一行",
            frame: CGRect(x: 10, y: 12, width: 120, height: 42),
            color: .blue,
            fontSize: 16
        )
        let id = store.append(original)
        let moved = ScreenshotAnnotation.text(
            text: "第一行\n第二行",
            frame: CGRect(x: 30, y: 22, width: 120, height: 48),
            color: .red,
            fontSize: 16
        )

        XCTAssertTrue(store.update(id: id, annotation: moved))
        XCTAssertEqual(store.items.map(\.id), [id])
        XCTAssertEqual(store.annotations, [moved])

        XCTAssertEqual(store.undo(), moved)
        XCTAssertEqual(store.items.map(\.id), [id])
        XCTAssertEqual(store.annotations, [original])
    }

    func testAnnotationStoreRestoresDeletedLabelAsOneUndoTransaction() {
        var store = ScreenshotAnnotationStore()
        let label = ScreenshotAnnotation.label(
            text: "重点区域",
            anchor: CGPoint(x: 36, y: 24),
            direction: .left,
            color: .orange,
            fontSize: 16,
            maximumWidth: 180
        )
        let id = store.append(label)

        XCTAssertEqual(store.remove(id: id), label)
        XCTAssertTrue(store.items.isEmpty)

        store.undo()
        XCTAssertEqual(store.items.map(\.id), [id])
        XCTAssertEqual(store.annotations, [label])
    }

    func testLabelLayoutFlipsBubbleAroundIndependentLocatorDot() {
        let left = ScreenshotTextLayout.labelGeometry(
            text: "标签",
            anchor: CGPoint(x: 100, y: 50),
            direction: .left,
            fontSize: 16,
            maximumWidth: 160
        )
        let right = ScreenshotTextLayout.labelGeometry(
            text: "标签",
            anchor: CGPoint(x: 100, y: 50),
            direction: .right,
            fontSize: 16,
            maximumWidth: 160
        )

        XCTAssertLessThan(left.dotRect.maxX, left.bubbleRect.minX)
        XCTAssertLessThan(right.bubbleRect.maxX, right.dotRect.minX)
        XCTAssertEqual(left.dotRect, right.dotRect)
        XCTAssertEqual(left.bubbleRect.size, right.bubbleRect.size)
    }

    func testMultilineTextLayoutGrowsWithAdditionalLine() {
        let oneLine = ScreenshotTextLayout.multilineSize(
            text: "第一行",
            fontSize: 16,
            maximumWidth: 120
        )
        let twoLines = ScreenshotTextLayout.multilineSize(
            text: "第一行\n第二行",
            fontSize: 16,
            maximumWidth: 120
        )

        XCTAssertGreaterThan(twoLines.height, oneLine.height)
    }

    func testLabelGeometryScalesWithImagePixelScale() {
        let oneX = ScreenshotTextLayout.labelGeometry(
            text: "定位",
            anchor: CGPoint(x: 60, y: 40),
            direction: .left,
            fontSize: 16,
            maximumWidth: 160
        )
        let twoX = ScreenshotTextLayout.labelGeometry(
            text: "定位",
            anchor: CGPoint(x: 120, y: 80),
            direction: .left,
            fontSize: 32,
            maximumWidth: 320
        )

        XCTAssertEqual(twoX.bubbleRect.width, oneX.bubbleRect.width * 2, accuracy: 4)
        XCTAssertEqual(twoX.bubbleRect.height, oneX.bubbleRect.height * 2, accuracy: 1)
        XCTAssertEqual(twoX.dotRect.width, oneX.dotRect.width * 2, accuracy: 0.001)
        XCTAssertEqual(twoX.cornerRadius, oneX.cornerRadius * 2, accuracy: 0.001)
    }

    func testTextResizePreservesTopAnchorAndKeepsFrameInsideImage() throws {
        let original = CGRect(x: 20, y: 40, width: 160, height: 64)
        let resized = try XCTUnwrap(
            ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                original,
                requiredHeight: 32,
                imageBounds: CGRect(x: 0, y: 0, width: 240, height: 160)
            )
        )

        XCTAssertEqual(resized.maxY, original.maxY)
        XCTAssertEqual(resized.height, 32)
        XCTAssertEqual(resized.origin.y, 72)
    }

    func testMovedLabelChoosesFittingDirectionAndStaysInsideImage() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 220, height: 100)
        let label = ScreenshotAnnotation.label(
            text: "靠近右侧边缘",
            anchor: CGPoint(x: 208, y: 94),
            direction: .left,
            color: .red,
            fontSize: 16,
            maximumWidth: 160
        )
        let constrained = try XCTUnwrap(
            ScreenshotAnnotationEditingPolicy.constrained(
                label,
                to: imageBounds,
                canFlipLabel: true
            )
        )

        XCTAssertTrue(imageBounds.contains(try XCTUnwrap(constrained.editableBounds)))
        guard case let .label(_, _, direction, _, _, _) = constrained else {
            return XCTFail("Expected a label")
        }
        XCTAssertEqual(direction, .right)
    }

    func testExplicitLabelFlipKeepsRequestedDirectionWhileConstrainingBounds() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 220, height: 100)
        let anchor = CGPoint(x: 100, y: 50)
        let label = ScreenshotAnnotation.label(
            text: "翻转",
            anchor: anchor,
            direction: .right,
            color: .blue,
            fontSize: 16,
            maximumWidth: 160
        )
        let constrained = try XCTUnwrap(
            ScreenshotAnnotationEditingPolicy.constrained(
                label,
                to: imageBounds,
                canFlipLabel: false
            )
        )

        XCTAssertTrue(imageBounds.contains(try XCTUnwrap(constrained.editableBounds)))
        guard case let .label(_, constrainedAnchor, direction, _, _, _) = constrained else {
            return XCTFail("Expected a label")
        }
        XCTAssertEqual(constrainedAnchor, anchor)
        XCTAssertEqual(direction, .right)
    }

    func testExplicitLabelFlipRejectsEdgeOverflowInsteadOfMovingLocator() {
        let label = ScreenshotAnnotation.label(
            text: "翻转",
            anchor: CGPoint(x: 12, y: 50),
            direction: .right,
            color: .blue,
            fontSize: 16,
            maximumWidth: 160
        )

        XCTAssertNil(
            ScreenshotAnnotationEditingPolicy.constrained(
                label,
                to: CGRect(x: 0, y: 0, width: 220, height: 100),
                canFlipLabel: false
            )
        )
    }

    func testLabelLocatorHasIndependentDirectInteractionTarget() {
        let label = ScreenshotAnnotation.label(
            text: "定位",
            anchor: CGPoint(x: 60, y: 40),
            direction: .left,
            color: .orange,
            fontSize: 16,
            maximumWidth: 160
        )
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: "定位",
            anchor: CGPoint(x: 60, y: 40),
            direction: .left,
            fontSize: 16,
            maximumWidth: 160
        )

        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.hitTarget(
                at: CGPoint(x: 60, y: 40),
                in: label
            ),
            .labelLocator
        )
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.hitTarget(
                at: CGPoint(x: geometry.bubbleRect.midX, y: geometry.bubbleRect.midY),
                in: label
            ),
            .body
        )
    }

    func testBlankEditDiscardsDraftWithoutDeletingExistingAnnotation() {
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.textCommitAction(for: " \n "),
            .discardDraft
        )
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.textCommitAction(for: "保留内容"),
            .commit
        )
    }

    func testTextAndLabelToolAvailabilityUsesApprovedMinimumCanvasSizes() {
        XCTAssertFalse(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .text,
                canvasSize: CGSize(width: 47, height: 32)
            )
        )
        XCTAssertTrue(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .text,
                canvasSize: CGSize(width: 48, height: 32)
            )
        )
        XCTAssertFalse(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: 71, height: 32)
            )
        )
        XCTAssertTrue(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: 72, height: 32)
            )
        )
    }

    func testEscapeRoutingLetsIMEConsumeMarkedTextBeforeEditorCommands() {
        XCTAssertEqual(
            ScreenshotEditorEscapePolicy.action(
                hasMarkedText: true,
                isEditing: true,
                hasSelection: true
            ),
            .forwardToInput
        )
        XCTAssertEqual(
            ScreenshotEditorEscapePolicy.action(
                hasMarkedText: false,
                isEditing: true,
                hasSelection: true
            ),
            .cancelEditing
        )
        XCTAssertEqual(
            ScreenshotEditorEscapePolicy.action(
                hasMarkedText: false,
                isEditing: false,
                hasSelection: true
            ),
            .deselect
        )
        XCTAssertEqual(
            ScreenshotEditorEscapePolicy.action(
                hasMarkedText: false,
                isEditing: false,
                hasSelection: false
            ),
            .cancelSession
        )
    }

    func testEditorCommandsStayWithNativeInputWhileEditing() {
        for command in [
            ScreenshotEditorCommand.undo,
            .delete,
            .complete
        ] {
            XCTAssertEqual(
                ScreenshotEditorCommandPolicy.action(
                    for: command,
                    isEditing: true,
                    hasSelection: true,
                    hasAnnotations: true
                ),
                .forwardToInput
            )
        }
    }

    func testEditorCommandsRouteByCommittedEditorState() {
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .undo,
                isEditing: false,
                hasSelection: false,
                hasAnnotations: true
            ),
            .undoAnnotation
        )
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .delete,
                isEditing: false,
                hasSelection: true,
                hasAnnotations: true
            ),
            .deleteSelection
        )
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .complete,
                isEditing: false,
                hasSelection: true,
                hasAnnotations: true
            ),
            .completeSession
        )
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .undo,
                isEditing: false,
                hasSelection: false,
                hasAnnotations: false
            ),
            .ignore
        )
    }
}
