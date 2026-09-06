import AppKit
import SwiftUI
import XCTest
@testable import MacToolsCore

final class MainPanelResizeGeometryTests: XCTestCase {
    @MainActor
    func testCachedCornerPathsMatchTheFullWindowContinuousRing() {
        let boundsList = [
            NSRect(x: 0, y: 0, width: 600, height: 414),
            NSRect(x: -120, y: 80, width: 720, height: 480),
            NSRect(x: 25, y: -60, width: 1100, height: 800)
        ]
        let offsets: [CGFloat] = [-0.25, 0.25, 0.5, 1.25, 4.25, 6.75, 8.25, 12.25, 20.25, 30.25, 38.25, 40.25, 50.25, 60.25, 79.25, 90.25]
        for bounds in boundsList {
            let outer = RoundedRectangle(cornerRadius: 40, style: .continuous).path(in: bounds).cgPath
            let inner = RoundedRectangle(cornerRadius: 32, style: .continuous)
                .path(in: bounds.insetBy(dx: 8, dy: 8)).cgPath
            for right in [false, true] {
                for top in [false, true] {
                    for x in offsets {
                        for y in offsets {
                            let point = mirroredPoint(NSPoint(x: x, y: y), in: bounds, right: right, top: top)
                            XCTAssertEqual(
                                MainPanelResizeEdge.hit(at: point, in: bounds) != nil,
                                outer.contains(point) && !inner.contains(point),
                                "\(bounds) \(point)"
                            )
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testResizeHitMatchesContinuousGlassAtPreviouslyMismatchedCornerPoints() {
        let bounds = NSRect(x: -120, y: 80, width: 720, height: 480)
        let visibleShape = RoundedRectangle(cornerRadius: 40, style: .continuous).path(in: bounds).cgPath
        let innerShape = RoundedRectangle(cornerRadius: 32, style: .continuous)
            .path(in: bounds.insetBy(dx: 8, dy: 8)).cgPath
        let outsidePoints = [NSPoint(x: 35, y: 0.5), NSPoint(x: 0.5, y: 35), NSPoint(x: 40, y: 0.25)]

        for right in [false, true] {
            for top in [false, true] {
                for offset in outsidePoints {
                    let point = mirroredPoint(offset, in: bounds, right: right, top: top)
                    XCTAssertFalse(visibleShape.contains(point))
                    XCTAssertNil(MainPanelResizeEdge.hit(at: point, in: bounds), "\(point)")
                }
                let point = mirroredPoint(NSPoint(x: 8.25, y: 38.25), in: bounds, right: right, top: top)
                XCTAssertTrue(visibleShape.contains(point))
                XCTAssertFalse(innerShape.contains(point))
                let expected: MainPanelResizeEdge = right
                    ? (top ? .topRight : .bottomRight)
                    : (top ? .topLeft : .bottomLeft)
                XCTAssertEqual(MainPanelResizeEdge.hit(at: point, in: bounds), expected, "\(point)")
            }
        }
    }

    @MainActor
    func testCursorTemplatesKeepExtendedCurveRegionsAtEveryCorner() {
        let bounds = NSRect(x: 25, y: -60, width: 1100, height: 800)
        let regions = MainPanelResizeEdge.cursorRegions(in: bounds)
        for right in [false, true] {
            for top in [false, true] {
                let horizontal = mirroredPoint(NSPoint(x: 50, y: 2), in: bounds, right: right, top: top)
                let vertical = mirroredPoint(NSPoint(x: 2, y: 50), in: bounds, right: right, top: top)
                for (point, expected) in [
                    (horizontal, top ? MainPanelResizeEdge.top : .bottom),
                    (vertical, right ? MainPanelResizeEdge.right : .left)
                ] {
                    XCTAssertEqual(Set(regions.filter { $0.rect.contains(point) }.map(\.edge)), [expected])
                    XCTAssertEqual(MainPanelResizeEdge.hit(at: point, in: bounds), expected)
                }
            }
        }
    }

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
                    x: view.bounds.minX + 80,
                    y: view.isFlipped ? view.bounds.minY : view.bounds.maxY - 8,
                    width: view.bounds.width - 160,
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

    private func mirroredPoint(_ offset: NSPoint, in bounds: NSRect, right: Bool, top: Bool) -> NSPoint {
        NSPoint(
            x: right ? bounds.maxX - offset.x : bounds.minX + offset.x,
            y: top ? bounds.maxY - offset.y : bounds.minY + offset.y
        )
    }
}

@MainActor
private final class FlippedResizeCoordinateView: NSView {
    override var isFlipped: Bool { true }
}
