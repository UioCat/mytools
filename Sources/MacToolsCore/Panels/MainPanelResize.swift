import AppKit
import SwiftUI

/// 主面板圆角内侧的缩放命中规则，与玻璃表面使用相同的连续圆角。
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

    // 连续圆角的曲线延伸超过标称半径；主面板最小尺寸足以容纳两侧延伸区。
    @MainActor
    private static let cornerExtent = MainPanelController.windowCornerRadius * 2

    @MainActor
    private static let cornerPaths: (outer: CGPath, inner: CGPath) = {
        let radius = MainPanelController.windowCornerRadius
        let bounds = NSRect(x: 0, y: 0, width: cornerExtent * 2, height: cornerExtent * 2)
        return (
            RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: bounds).cgPath,
            RoundedRectangle(cornerRadius: radius - 8, style: .continuous)
                .path(in: bounds.insetBy(dx: 8, dy: 8)).cgPath
        )
    }()

    @MainActor
    static func hit(at point: NSPoint, in bounds: NSRect) -> Self? {
        let radius = MainPanelController.windowCornerRadius
        // 四角对称，直边向参考形状中部投影；无需随窗口尺寸重新创建路径。
        let cornerPoint = NSPoint(
            x: min(cornerExtent, min(point.x - bounds.minX, bounds.maxX - point.x)),
            y: min(cornerExtent, min(point.y - bounds.minY, bounds.maxY - point.y))
        )
        guard cornerPaths.outer.contains(cornerPoint), !cornerPaths.inner.contains(cornerPoint) else { return nil }

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
    private static let cornerCursorRegions: [(region: MainPanelCursorRegion, right: Bool, top: Bool)] = {
        let referenceBounds = NSRect(x: 0, y: 0, width: cornerExtent * 3, height: cornerExtent * 3)
        let step: CGFloat = 4
        var regions: [(region: MainPanelCursorRegion, right: Bool, top: Bool)] = []
        for right in [false, true] {
            for top in [false, true] {
                let xOrigin = right ? referenceBounds.maxX - cornerExtent : referenceBounds.minX
                let yOrigin = top ? referenceBounds.maxY - cornerExtent : referenceBounds.minY
                for x in stride(from: CGFloat(0), to: cornerExtent, by: step) {
                    for y in stride(from: CGFloat(0), to: cornerExtent, by: step) {
                        let point = NSPoint(x: xOrigin + x + step / 2, y: yOrigin + y + step / 2)
                        if let edge = hit(at: point, in: referenceBounds) {
                            regions.append((
                                MainPanelCursorRegion(rect: NSRect(x: x, y: y, width: step, height: step), edge: edge),
                                right,
                                top
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
        let inset: CGFloat = 8
        var regions = [
            MainPanelCursorRegion(rect: NSRect(x: bounds.minX, y: bounds.minY + cornerExtent, width: inset, height: bounds.height - 2 * cornerExtent), edge: .left),
            MainPanelCursorRegion(rect: NSRect(x: bounds.maxX - inset, y: bounds.minY + cornerExtent, width: inset, height: bounds.height - 2 * cornerExtent), edge: .right),
            MainPanelCursorRegion(rect: NSRect(x: bounds.minX + cornerExtent, y: bounds.minY, width: bounds.width - 2 * cornerExtent, height: inset), edge: .bottom),
            MainPanelCursorRegion(rect: NSRect(x: bounds.minX + cornerExtent, y: bounds.maxY - inset, width: bounds.width - 2 * cornerExtent, height: inset), edge: .top)
        ]
        regions.reserveCapacity(regions.count + cornerCursorRegions.count)
        for template in cornerCursorRegions {
            regions.append(MainPanelCursorRegion(
                rect: template.region.rect.offsetBy(
                    dx: template.right ? bounds.maxX - cornerExtent : bounds.minX,
                    dy: template.top ? bounds.maxY - cornerExtent : bounds.minY
                ),
                edge: template.region.edge
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
