// 截图文本与标签编辑的纯状态策略，集中处理边界、命中和命令优先级。

import CoreGraphics
import Foundation

public enum ScreenshotEditableHitTarget: Equatable, Sendable {
    case body
    case labelLocator
}

public enum ScreenshotTextCommitAction: Equatable, Sendable {
    case commit
    case discardDraft
}

public enum ScreenshotEditorEscapeAction: Equatable, Sendable {
    case forwardToInput
    case cancelEditing
    case deselect
    case cancelSession
}

public enum ScreenshotEditorCommand: Equatable, Sendable {
    case undo
    case delete
    case complete
}

public enum ScreenshotEditorCommandAction: Equatable, Sendable {
    case forwardToInput
    case undoAnnotation
    case deleteSelection
    case completeSession
    case ignore
}

public enum ScreenshotEditorCommandPolicy {
    public static func action(
        for command: ScreenshotEditorCommand,
        isEditing: Bool,
        hasSelection: Bool,
        canUndo: Bool
    ) -> ScreenshotEditorCommandAction {
        if isEditing {
            return .forwardToInput
        }
        switch command {
        case .undo:
            return canUndo ? .undoAnnotation : .ignore
        case .delete:
            return hasSelection ? .deleteSelection : .ignore
        case .complete:
            return .completeSession
        }
    }
}

public enum ScreenshotEditorEscapePolicy {
    public static func action(
        hasMarkedText: Bool,
        isEditing: Bool,
        hasSelection: Bool
    ) -> ScreenshotEditorEscapeAction {
        if hasMarkedText {
            return .forwardToInput
        }
        if isEditing {
            return .cancelEditing
        }
        if hasSelection {
            return .deselect
        }
        return .cancelSession
    }
}

public enum ScreenshotAnnotationEditingPolicy {
    public static let minimumTextCanvasSize = CGSize(width: 48, height: 32)
    public static let minimumLabelCanvasSize = CGSize(
        width: minimumLabelCanvasWidth(for: 16),
        height: minimumLabelCanvasHeight(for: 16)
    )

    public static func minimumLabelCanvasWidth(for fontSize: CGFloat) -> CGFloat {
        max(
            72,
            ceil(
                16
                    + ScreenshotLabelStyle.dotDiameter(for: fontSize)
                    + ScreenshotLabelStyle.labelGap(for: fontSize)
                    + ScreenshotLabelStyle.visualOutset(for: fontSize)
                    + ScreenshotLabelStyle.horizontalPadding(for: fontSize) * 2
                    + ScreenshotTextLayout.minimumSingleLineTruncationWidth(
                        fontSize: fontSize
                    )
            )
        )
    }

    public static func minimumLabelCanvasHeight(for fontSize: CGFloat) -> CGFloat {
        ceil(
            ScreenshotTextLayout.labelGeometry(
                text: " ",
                anchor: .zero,
                direction: .left,
                fontSize: fontSize,
                maximumWidth: .greatestFiniteMagnitude
            ).bounds.height
        )
    }

    public static func canUse(
        tool: ScreenshotAnnotationTool,
        canvasSize: CGSize,
        labelFontSize: CGFloat = 16
    ) -> Bool {
        switch tool {
        case .text:
            return canvasSize.width >= minimumTextCanvasSize.width
                && canvasSize.height >= minimumTextCanvasSize.height
        case .label:
            return canvasSize.width >= minimumLabelCanvasWidth(for: labelFontSize)
                && canvasSize.height >= minimumLabelCanvasHeight(for: labelFontSize)
        case .line, .freehand, .arrow, .rectangle, .mosaic:
            return true
        }
    }

    public static func textCommitAction(for text: String) -> ScreenshotTextCommitAction {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .discardDraft
            : .commit
    }

    public static func resizedTextFramePreservingTop(
        _ frame: CGRect,
        requiredHeight: CGFloat,
        imageBounds: CGRect
    ) -> CGRect? {
        resizedTextFramePreservingTop(
            frame,
            requiredSize: CGSize(width: frame.standardized.width, height: requiredHeight),
            imageBounds: imageBounds
        )
    }

    public static func resizedTextFramePreservingTop(
        _ frame: CGRect,
        requiredSize: CGSize,
        imageBounds: CGRect
    ) -> CGRect? {
        let bounds = imageBounds.standardized
        let frame = frame.standardized
        guard requiredSize.width > 0,
              requiredSize.height > 0,
              requiredSize.width <= bounds.width,
              requiredSize.height <= bounds.height else {
            return nil
        }
        let resized = CGRect(
            x: frame.minX,
            y: frame.maxY - requiredSize.height,
            width: requiredSize.width,
            height: requiredSize.height
        )
        return constrainedRect(resized, to: bounds)
    }

    public static func hitTarget(
        at point: CGPoint,
        in annotation: ScreenshotAnnotation,
        tolerance: CGFloat = 0
    ) -> ScreenshotEditableHitTarget? {
        switch annotation {
        case let .label(text, anchor, direction, _, fontSize, maximumWidth):
            let geometry = ScreenshotTextLayout.labelGeometry(
                text: text,
                anchor: anchor,
                direction: direction,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
            if geometry.dotRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) {
                return .labelLocator
            }
            return geometry.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                ? .body
                : nil
        case let .text(_, frame, _, _):
            return frame.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
                ? .body
                : nil
        case .line, .freehand, .arrow, .rectangle, .mosaic:
            return nil
        }
    }

    public static func constrained(
        _ annotation: ScreenshotAnnotation,
        to imageBounds: CGRect,
        canFlipLabel: Bool
    ) -> ScreenshotAnnotation? {
        let bounds = imageBounds.standardized
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        switch annotation {
        case let .text(text, frame, color, fontSize):
            guard let constrainedFrame = constrainedRect(frame.standardized, to: bounds) else {
                return nil
            }
            return .text(text: text, frame: constrainedFrame, color: color, fontSize: fontSize)
        case let .label(text, anchor, direction, color, fontSize, maximumWidth):
            if !canFlipLabel {
                let geometry = ScreenshotTextLayout.labelGeometry(
                    text: text,
                    anchor: anchor,
                    direction: direction,
                    fontSize: fontSize,
                    maximumWidth: maximumWidth
                )
                guard contains(geometry.bounds, inside: bounds) else {
                    return nil
                }
                return annotation
            }
            let directions = canFlipLabel ? [direction, direction.flipped] : [direction]
            guard let best = directions
                .map({ candidateDirection in
                    let geometry = ScreenshotTextLayout.labelGeometry(
                        text: text,
                        anchor: anchor,
                        direction: candidateDirection,
                        fontSize: fontSize,
                        maximumWidth: maximumWidth
                    )
                    return (
                        candidateDirection: candidateDirection,
                        geometry: geometry,
                        overflow: overflow(of: geometry.bounds, outside: bounds)
                    )
                })
                .min(by: { $0.overflow < $1.overflow }),
                best.geometry.bounds.width <= bounds.width,
                best.geometry.bounds.height <= bounds.height else {
                return nil
            }
            let translation = translationToFit(best.geometry.bounds, inside: bounds)
            return .label(
                text: text,
                anchor: CGPoint(x: anchor.x + translation.width, y: anchor.y + translation.height),
                direction: best.candidateDirection,
                color: color,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
        case .line, .freehand, .arrow, .rectangle, .mosaic:
            return annotation
        }
    }

    private static func constrainedRect(_ rect: CGRect, to bounds: CGRect) -> CGRect? {
        guard rect.width <= bounds.width, rect.height <= bounds.height else {
            return nil
        }
        return CGRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - rect.width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    private static func overflow(of rect: CGRect, outside bounds: CGRect) -> CGFloat {
        max(0, bounds.minX - rect.minX)
            + max(0, rect.maxX - bounds.maxX)
            + max(0, bounds.minY - rect.minY)
            + max(0, rect.maxY - bounds.maxY)
    }

    private static func translationToFit(_ rect: CGRect, inside bounds: CGRect) -> CGSize {
        let horizontalSlack = max(0, bounds.width - rect.width)
        let verticalSlack = max(0, bounds.height - rect.height)
        let horizontalSafetyInset = min(0.001, horizontalSlack / 2)
        let verticalSafetyInset = min(0.001, verticalSlack / 2)
        let dx: CGFloat
        if rect.minX < bounds.minX + horizontalSafetyInset {
            dx = bounds.minX + horizontalSafetyInset - rect.minX
        } else if rect.maxX > bounds.maxX - horizontalSafetyInset {
            dx = bounds.maxX - horizontalSafetyInset - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if rect.minY < bounds.minY + verticalSafetyInset {
            dy = bounds.minY + verticalSafetyInset - rect.minY
        } else if rect.maxY > bounds.maxY - verticalSafetyInset {
            dy = bounds.maxY - verticalSafetyInset - rect.maxY
        } else {
            dy = 0
        }
        return CGSize(width: dx, height: dy)
    }

    private static func contains(_ rect: CGRect, inside bounds: CGRect) -> Bool {
        bounds.insetBy(dx: -0.001, dy: -0.001).contains(rect)
    }
}
