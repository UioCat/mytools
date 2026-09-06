import AppKit
import SwiftUI

/// 无边框窗口没有 AppKit 标题框架的缩放命中区，显式保留圆角内侧的拖动区域。
enum MainPanelResizeEdge: CaseIterable, Hashable {
    case left, right, bottom, top, bottomLeft, bottomRight, topLeft, topRight

    var movesLeft: Bool { self == .left || self == .bottomLeft || self == .topLeft }
    var movesRight: Bool { self == .right || self == .bottomRight || self == .topRight }
    var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }

    @MainActor
    var cursor: NSCursor {
        Self.cursors[self]!
    }

    @MainActor
    private static let cursors: [Self: NSCursor] = Dictionary(uniqueKeysWithValues: allCases.map { edge in
        let position: NSCursor.FrameResizePosition
        switch edge {
        case .left: position = .left
        case .right: position = .right
        case .bottom: position = .bottom
        case .top: position = .top
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        }
        return (edge, .frameResize(position: position, directions: [.inward, .outward]))
    })

    @MainActor
    static func hit(at point: NSPoint, in bounds: NSRect) -> Self? {
        let radius = MainPanelController.windowCornerRadius
        let inset: CGFloat = 8
        let outer = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        let inner = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: radius - inset,
            yRadius: radius - inset
        )
        guard outer.contains(point), !inner.contains(point) else { return nil }

        let left = point.x < bounds.minX + radius
        let right = point.x > bounds.maxX - radius
        let bottom = point.y < bounds.minY + radius
        let top = point.y > bounds.maxY - radius
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left { return .left }
        if right { return .right }
        return bottom ? .bottom : .top
    }

    /// 只缓存固定圆角内的相对网格，不随窗口尺寸累计缓存。
    @MainActor
    private static let cornerCursorRegions: [MainPanelCursorRegion] = {
        let radius = MainPanelController.windowCornerRadius
        let referenceBounds = NSRect(x: 0, y: 0, width: radius * 3, height: radius * 3)
        let step: CGFloat = 4
        var regions: [MainPanelCursorRegion] = []
        for xOrigin in [referenceBounds.minX, referenceBounds.maxX - radius] {
            for yOrigin in [referenceBounds.minY, referenceBounds.maxY - radius] {
                for x in stride(from: CGFloat(0), to: radius, by: step) {
                    for y in stride(from: CGFloat(0), to: radius, by: step) {
                        let point = NSPoint(x: xOrigin + x + step / 2, y: yOrigin + y + step / 2)
                        if let edge = hit(at: point, in: referenceBounds) {
                            regions.append(MainPanelCursorRegion(
                                rect: NSRect(x: x, y: y, width: step, height: step),
                                edge: edge
                            ))
                        }
                    }
                }
            }
        }
        return regions
    }()

    @MainActor
    static func cursorRegions(in bounds: NSRect) -> [MainPanelCursorRegion] {
        let radius = MainPanelController.windowCornerRadius
        let inset: CGFloat = 8
        var regions = [
            MainPanelCursorRegion(rect: NSRect(x: bounds.minX, y: bounds.minY + radius, width: inset, height: bounds.height - 2 * radius), edge: .left),
            MainPanelCursorRegion(rect: NSRect(x: bounds.maxX - inset, y: bounds.minY + radius, width: inset, height: bounds.height - 2 * radius), edge: .right),
            MainPanelCursorRegion(rect: NSRect(x: bounds.minX + radius, y: bounds.minY, width: bounds.width - 2 * radius, height: inset), edge: .bottom),
            MainPanelCursorRegion(rect: NSRect(x: bounds.minX + radius, y: bounds.maxY - inset, width: bounds.width - 2 * radius, height: inset), edge: .top)
        ]
        regions.reserveCapacity(regions.count + cornerCursorRegions.count)
        for region in cornerCursorRegions {
            regions.append(MainPanelCursorRegion(
                rect: region.rect.offsetBy(
                    dx: region.edge.movesRight ? bounds.maxX - radius : bounds.minX,
                    dy: region.edge.movesTop ? bounds.maxY - radius : bounds.minY
                ),
                edge: region.edge
            ))
        }
        return regions
    }

    /// 命中区始终按窗口坐标定义，再转换到可能翻转的宿主视图。
    @MainActor
    static func cursorRegions(in view: NSView) -> [MainPanelCursorRegion] {
        cursorRegions(in: view.convert(view.bounds, to: nil)).map { region in
            MainPanelCursorRegion(rect: view.convert(region.rect, from: nil), edge: region.edge)
        }
    }

    func resizedFrame(from initial: NSRect, delta: NSPoint, minimum: NSSize, maximum: NSSize) -> NSRect {
        var result = initial
        if movesLeft || movesRight {
            result.size.width = min(maximum.width, max(minimum.width, initial.width + (movesLeft ? -delta.x : delta.x)))
            if movesLeft { result.origin.x = initial.maxX - result.width }
        }
        if movesBottom || movesTop {
            result.size.height = min(maximum.height, max(minimum.height, initial.height + (movesBottom ? -delta.y : delta.y)))
            if movesBottom { result.origin.y = initial.maxY - result.height }
        }
        return result
    }
}

struct MainPanelCursorRegion: Equatable {
    let rect: NSRect
    let edge: MainPanelResizeEdge
}

/// 光标与拖动使用同一命中规则，不在输入框或按钮上设置缩放光标。
@MainActor
final class MainPanelHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        super.resetCursorRects()
        for region in MainPanelResizeEdge.cursorRegions(in: self) {
            addCursorRect(region.rect, cursor: region.edge.cursor)
        }
    }
}
