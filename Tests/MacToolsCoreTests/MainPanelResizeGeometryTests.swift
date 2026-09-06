import AppKit
import XCTest
@testable import MacToolsCore

final class MainPanelResizeGeometryTests: XCTestCase {
    @MainActor
    func testCursorRegionsFollowResizeEdgesAcrossSizesAndOrigins() {
        let boundsList = [
            NSRect(x: 0, y: 0, width: 600, height: 414),
            NSRect(x: -120, y: 80, width: 720, height: 480),
            NSRect(x: 25, y: -60, width: 1100, height: 800)
        ]

        for bounds in boundsList {
            let regions = MainPanelResizeEdge.cursorRegions(in: bounds)
            for region in regions {
                XCTAssertTrue(bounds.contains(region.rect))
                XCTAssertEqual(
                    MainPanelResizeEdge.hit(at: NSPoint(x: region.rect.midX, y: region.rect.midY), in: bounds),
                    region.edge
                )
            }
            assertEdgePoints(in: bounds, regions: regions, flipped: false)
            for point in [
                NSPoint(x: bounds.midX, y: bounds.midY),
                NSPoint(x: bounds.minX + 2, y: bounds.minY + 2),
                NSPoint(x: bounds.minX + 40, y: bounds.minY + 40),
                NSPoint(x: bounds.minX + 20, y: bounds.midY)
            ] {
                XCTAssertFalse(regions.contains { $0.rect.contains(point) })
                XCTAssertNil(MainPanelResizeEdge.hit(at: point, in: bounds))
            }
        }
    }

    @MainActor
    func testCursorRegionsConvertWindowDirectionsIntoFlippedAndOffsetViewBounds() {
        _ = NSApplication.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        defer { panel.orderOut(nil) }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 720))
        panel.contentView = container
        let frame = NSRect(x: 37, y: 53, width: 720, height: 480)
        let views: [NSView] = [NSView(frame: frame), FlippedResizeCoordinateView(frame: frame)]

        for view in views {
            container.addSubview(view)
            view.bounds.origin = NSPoint(x: 100, y: -80)
            let regions = MainPanelResizeEdge.cursorRegions(in: view)

            assertEdgePoints(in: view.bounds, regions: regions, flipped: view.isFlipped)
            XCTAssertEqual(
                regions.first { $0.edge == .top }?.rect,
                NSRect(
                    x: view.bounds.minX + 40,
                    y: view.isFlipped ? view.bounds.minY : view.bounds.maxY - 8,
                    width: view.bounds.width - 80,
                    height: 8
                )
            )
            view.removeFromSuperview()
        }
    }

    @MainActor
    private func assertEdgePoints(
        in bounds: NSRect,
        regions: [MainPanelCursorRegion],
        flipped: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let points: [(NSPoint, MainPanelResizeEdge)] = [
            (NSPoint(x: bounds.minX + 4, y: bounds.midY), .left),
            (NSPoint(x: bounds.maxX - 4, y: bounds.midY), .right),
            (NSPoint(x: bounds.midX, y: bounds.minY + 4), flipped ? .top : .bottom),
            (NSPoint(x: bounds.midX, y: bounds.maxY - 4), flipped ? .bottom : .top),
            (NSPoint(x: bounds.minX + 14, y: bounds.minY + 14), flipped ? .topLeft : .bottomLeft),
            (NSPoint(x: bounds.maxX - 14, y: bounds.minY + 14), flipped ? .topRight : .bottomRight),
            (NSPoint(x: bounds.minX + 14, y: bounds.maxY - 14), flipped ? .bottomLeft : .topLeft),
            (NSPoint(x: bounds.maxX - 14, y: bounds.maxY - 14), flipped ? .bottomRight : .topRight)
        ]
        for (point, expected) in points {
            let matchingEdges = Set(regions.filter { $0.rect.contains(point) }.map(\.edge))
            XCTAssertEqual(matchingEdges, [expected], "\(point)", file: file, line: line)
        }
    }
}

@MainActor
private final class FlippedResizeCoordinateView: NSView {
    override var isFlipped: Bool { true }
}
