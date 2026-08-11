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

    func testDeletingLastAnnotationKeepsEditorUndoAvailable() {
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
        XCTAssertTrue(store.annotations.isEmpty)
        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .undo,
                isEditing: false,
                hasSelection: false,
                canUndo: store.canUndo
            ),
            .undoAnnotation
        )
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

    func testLabelGeometryAdaptsToContentWithoutClippingShortText() {
        let shortText = "hello"
        let short = ScreenshotTextLayout.labelGeometry(
            text: shortText,
            anchor: CGPoint(x: 40, y: 50),
            direction: .left,
            fontSize: 16,
            maximumWidth: 400
        )
        let long = ScreenshotTextLayout.labelGeometry(
            text: "hello，欢迎使用截图标签",
            anchor: CGPoint(x: 40, y: 50),
            direction: .left,
            fontSize: 16,
            maximumWidth: 400
        )
        let metrics = ScreenshotTextLayout.singleLineMetrics(
            text: shortText,
            fontSize: 16,
            weight: .medium
        )

        XCTAssertGreaterThan(short.textRect.width, ceil(metrics.width))
        XCTAssertLessThan(short.bubbleRect.width, long.bubbleRect.width)
        XCTAssertLessThan(long.bubbleRect.width, 400)
    }

    func testLabelGeometryOnlyCapsLongTextAtAvailableWidth() {
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: String(repeating: "自适应宽度", count: 20),
            anchor: CGPoint(x: 40, y: 50),
            direction: .left,
            fontSize: 16,
            maximumWidth: 180
        )

        XCTAssertEqual(geometry.bubbleRect.width, 180, accuracy: 0.001)
    }

    func testLabelTextBaselineIsTypographicallyCentered() {
        let text = "Ag 你好"
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: text,
            anchor: CGPoint(x: 40, y: 50),
            direction: .left,
            fontSize: 16,
            maximumWidth: 240
        )
        let metrics = ScreenshotTextLayout.singleLineMetrics(
            text: text,
            fontSize: 16,
            weight: .medium
        )

        XCTAssertEqual(
            geometry.textBaselineY + (metrics.ascent - metrics.descent) / 2,
            geometry.textRect.midY,
            accuracy: 0.001
        )
    }

    func testLabelStyleKeepsTextReadableOnLightAndDarkScreens() {
        for backgroundLevel in [CGFloat(0), CGFloat(1)] {
            let surface = ScreenshotLabelStyle.backgroundColor.composited(over: backgroundLevel)
            let contrast = contrastRatio(
                ScreenshotLabelStyle.foregroundColor.relativeLuminance,
                surface.relativeLuminance
            )

            XCTAssertGreaterThanOrEqual(contrast, 7)
        }
    }

    func testLabelMaximumWidthUsesAvailableCanvasInsteadOfLegacyFixedCap() {
        let maximumWidth = ScreenshotLabelStyle.maximumBubbleWidth(
            in: 800,
            fontSize: 16,
            edgeInset: 8
        )

        XCTAssertGreaterThan(maximumWidth, 700)
    }

    func testLabelMaximumWidthNormalizationReplacesLegacyFixedCap() {
        let normalized = ScreenshotLabelStyle.normalizedMaximumBubbleWidth(
            existingMaximumWidth: 240,
            in: 800,
            fontSize: 16,
            edgeInset: 8
        )

        XCTAssertEqual(
            normalized,
            ScreenshotLabelStyle.maximumBubbleWidth(
                in: 800,
                fontSize: 16,
                edgeInset: 8
            ),
            accuracy: 0.001
        )
        XCTAssertGreaterThan(normalized, 700)
    }

    func testLabelBoundsIncludeBorderAndDownwardScreenShadow() {
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: "边界",
            anchor: CGPoint(x: 60, y: 40),
            direction: .left,
            fontSize: 16,
            maximumWidth: 160
        )

        XCTAssertLessThan(geometry.bounds.minX, geometry.bubbleRect.minX)
        XCTAssertLessThan(geometry.bounds.minY, geometry.bubbleRect.minY)
        XCTAssertGreaterThan(geometry.bounds.maxX, geometry.bubbleRect.maxX)
        XCTAssertGreaterThan(geometry.bounds.maxY, geometry.bubbleRect.maxY)
        XCTAssertLessThan(ScreenshotLabelStyle.imageShadowYOffset(for: 16), 0)
        XCTAssertEqual(
            ScreenshotLabelStyle.imageShadowYOffset(for: 16),
            -ScreenshotLabelStyle.shadowYOffset(for: 16),
            accuracy: 0.001
        )
    }

    func testChangingLabelFontSizeRefreshesItsCanvasWidthLimit() {
        let largeMaximumWidth = ScreenshotLabelStyle.maximumBubbleWidth(
            in: 72,
            fontSize: 24,
            edgeInset: 8
        )
        let unchangedMaximumWidth = ScreenshotLabelStyle.resolvedMaximumBubbleWidth(
            existingMaximumWidth: largeMaximumWidth,
            in: 72,
            requestedFontSize: nil,
            edgeInset: 8
        )
        let smallMaximumWidth = ScreenshotLabelStyle.resolvedMaximumBubbleWidth(
            existingMaximumWidth: largeMaximumWidth,
            in: 72,
            requestedFontSize: 12,
            edgeInset: 8
        )

        XCTAssertEqual(unchangedMaximumWidth, largeMaximumWidth)
        XCTAssertGreaterThan(smallMaximumWidth, largeMaximumWidth)
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

    func testPlainTextFittedSizeHugsShortContentAndWrapsAtCanvasLimit() {
        let short = ScreenshotTextLayout.fittedMultilineSize(
            text: "333",
            fontSize: 16,
            maximumWidth: 360,
            minimumSize: CGSize(width: 1, height: 1)
        )
        let wrapped = ScreenshotTextLayout.fittedMultilineSize(
            text: String(repeating: "自适应文本", count: 20),
            fontSize: 16,
            maximumWidth: 120,
            minimumSize: CGSize(width: 1, height: 1)
        )

        XCTAssertLessThan(short.width, 64)
        XCTAssertGreaterThan(short.width, ScreenshotTextLayout.singleLineWidth(text: "333", fontSize: 16))
        XCTAssertEqual(wrapped.width, 120, accuracy: 0.001)
        XCTAssertGreaterThan(wrapped.height, short.height)
    }

    func testPlainTextAtMaximumWidthStaysInsideHorizontalSafeArea() throws {
        let safeBounds = CGRect(x: 8, y: 0, width: 384, height: 300)
        let requiredSize = ScreenshotTextLayout.fittedMultilineSize(
            text: String(repeating: "自适应文本", count: 20),
            fontSize: 16,
            maximumWidth: safeBounds.width,
            minimumSize: CGSize(width: 1, height: 1)
        )
        let resized = try XCTUnwrap(
            ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                CGRect(x: 300, y: 120, width: 48, height: 32),
                requiredSize: requiredSize,
                imageBounds: safeBounds
            )
        )

        XCTAssertEqual(requiredSize.width, safeBounds.width, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(resized.minX, safeBounds.minX)
        XCTAssertLessThanOrEqual(resized.maxX, safeBounds.maxX)
    }

    private func contrastRatio(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let lighter = max(lhs, rhs)
        let darker = min(lhs, rhs)
        return (lighter + 0.05) / (darker + 0.05)
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

    func testLabelStyleMetricsScaleWithImagePixelScale() {
        XCTAssertEqual(
            ScreenshotLabelStyle.horizontalPadding(for: 24),
            ScreenshotLabelStyle.horizontalPadding(for: 12) * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotLabelStyle.verticalPadding(for: 24),
            ScreenshotLabelStyle.verticalPadding(for: 12) * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotLabelStyle.glyphSafetyWidth(for: 24),
            ScreenshotLabelStyle.glyphSafetyWidth(for: 12) * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotLabelStyle.borderWidth(for: 24),
            ScreenshotLabelStyle.borderWidth(for: 12) * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotLabelStyle.shadowRadius(for: 24),
            ScreenshotLabelStyle.shadowRadius(for: 12) * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotLabelStyle.shadowYOffset(for: 24),
            ScreenshotLabelStyle.shadowYOffset(for: 12) * 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScreenshotLabelStyle.visualOutset(for: 24),
            ScreenshotLabelStyle.visualOutset(for: 12) * 2,
            accuracy: 0.001
        )
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

        let editableBounds = try XCTUnwrap(constrained.editableBounds)
        XCTAssertTrue(
            imageBounds.contains(editableBounds),
            "Expected \(editableBounds) inside \(imageBounds)"
        )
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

    func testEdgeConstrainedLabelCanStillFlipWhenBothSidesFit() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 200, height: 44)
        let constrained = try XCTUnwrap(
            ScreenshotAnnotationEditingPolicy.constrained(
                .label(
                    text: "翻转",
                    anchor: CGPoint(x: 100, y: 22),
                    direction: .left,
                    color: .blue,
                    fontSize: 16,
                    maximumWidth: 160
                ),
                to: imageBounds,
                canFlipLabel: true
            )
        )
        let editableBounds = try XCTUnwrap(constrained.editableBounds)
        XCTAssertTrue(imageBounds.contains(editableBounds))
        guard case let .label(text, anchor, direction, color, fontSize, maximumWidth) = constrained else {
            return XCTFail("Expected a label")
        }

        XCTAssertNotNil(
            ScreenshotAnnotationEditingPolicy.constrained(
                .label(
                    text: text,
                    anchor: anchor,
                    direction: direction.flipped,
                    color: color,
                    fontSize: fontSize,
                    maximumWidth: maximumWidth
                ),
                to: imageBounds,
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

    func testTextAndLabelToolAvailabilityUsesCompleteVisualBounds() throws {
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
        let mediumMinimumWidth = ScreenshotAnnotationEditingPolicy.minimumLabelCanvasWidth(
            for: 16
        )
        XCTAssertFalse(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: mediumMinimumWidth - 1, height: 44)
            )
        )
        XCTAssertFalse(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: 72, height: 43)
            )
        )
        XCTAssertTrue(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: mediumMinimumWidth, height: 44)
            )
        )
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.minimumLabelCanvasHeight(for: 12),
            33
        )
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.minimumLabelCanvasHeight(for: 16),
            44
        )
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.minimumLabelCanvasHeight(for: 24),
            66
        )
        XCTAssertEqual(
            ScreenshotAnnotationEditingPolicy.minimumLabelCanvasWidth(for: 12),
            72
        )
        XCTAssertGreaterThanOrEqual(mediumMinimumWidth, 72)
        let largeMinimumWidth = ScreenshotAnnotationEditingPolicy.minimumLabelCanvasWidth(
            for: 24
        )
        XCTAssertGreaterThan(largeMinimumWidth, 72)
        XCTAssertFalse(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: largeMinimumWidth - 1, height: 66),
                labelFontSize: 24
            )
        )
        XCTAssertTrue(
            ScreenshotAnnotationEditingPolicy.canUse(
                tool: .label,
                canvasSize: CGSize(width: largeMinimumWidth, height: 66),
                labelFontSize: 24
            )
        )

        let imageBounds = CGRect(x: 0, y: 0, width: mediumMinimumWidth, height: 44)
        let fontSize: CGFloat = 16
        let label = ScreenshotAnnotation.label(
            text: "输入标签",
            anchor: CGPoint(x: imageBounds.midX, y: imageBounds.midY),
            direction: .left,
            color: .red,
            fontSize: fontSize,
            maximumWidth: ScreenshotLabelStyle.maximumBubbleWidth(
                in: imageBounds.width,
                fontSize: fontSize,
                edgeInset: 8
            )
        )
        let constrained = try XCTUnwrap(
            ScreenshotAnnotationEditingPolicy.constrained(
                label,
                to: imageBounds,
                canFlipLabel: true
            )
        )
        let editableBounds = try XCTUnwrap(constrained.editableBounds)
        XCTAssertTrue(
            imageBounds.contains(editableBounds),
            "Expected \(editableBounds) inside \(imageBounds)"
        )

        guard case let .label(text, anchor, direction, color, constrainedFontSize, maximumWidth) = constrained else {
            return XCTFail("Expected a label")
        }
        let stableConstraint = ScreenshotAnnotationEditingPolicy.constrained(
            .label(
                text: text,
                anchor: anchor,
                direction: direction,
                color: color,
                fontSize: constrainedFontSize,
                maximumWidth: maximumWidth
            ),
            to: imageBounds,
            canFlipLabel: false
        )
        XCTAssertNotNil(stableConstraint)

        let tooNarrowLargeLabel = ScreenshotAnnotation.label(
            text: "大字号标签",
            anchor: CGPoint(x: 36, y: 50),
            direction: .left,
            color: .red,
            fontSize: 24,
            maximumWidth: ScreenshotLabelStyle.maximumBubbleWidth(
                in: 72,
                fontSize: 24,
                edgeInset: 8
            )
        )
        XCTAssertNil(
            ScreenshotAnnotationEditingPolicy.constrained(
                tooNarrowLargeLabel,
                to: CGRect(x: 0, y: 0, width: 72, height: 100),
                canFlipLabel: true
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
                    canUndo: true
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
                canUndo: true
            ),
            .undoAnnotation
        )
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .delete,
                isEditing: false,
                hasSelection: true,
                canUndo: true
            ),
            .deleteSelection
        )
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .complete,
                isEditing: false,
                hasSelection: true,
                canUndo: true
            ),
            .completeSession
        )
        XCTAssertEqual(
            ScreenshotEditorCommandPolicy.action(
                for: .undo,
                isEditing: false,
                hasSelection: false,
                canUndo: false
            ),
            .ignore
        )
    }
}
