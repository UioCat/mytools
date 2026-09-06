import AppKit
import SwiftUI
import XCTest
@testable import MacToolsCore

final class MainPanelControllerTests: XCTestCase {
    func testMainPanelCentersOnlyForItsFirstPresentation() {
        XCTAssertEqual(
            MainPanelPositioningPolicy.decision(hasExistingPanel: false),
            .center
        )
        XCTAssertEqual(
            MainPanelPositioningPolicy.decision(hasExistingPanel: true),
            .preserveCurrentFrame
        )
    }

    @MainActor
    func testMainPanelKeepsNativeResizeWithoutRectangularSystemShadow() {
        let styleMask = MainPanelController.windowStyleMask

        XCTAssertTrue(styleMask.contains(.titled))
        XCTAssertTrue(styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(styleMask.contains(.resizable))
        XCTAssertFalse(MainPanelController.usesSystemWindowShadow)
        XCTAssertEqual(MainPanelController.windowCornerRadius, 40)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        MainPanelController.configureWindowChrome(panel)
        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertNotEqual(panel.standardWindowButton(button)?.isHidden, false)
        }
    }

    @MainActor
    func testHostingViewExtendsGlassIntoTheHiddenTitlebar() {
        let view = MainPanelHostingView(rootView: Color.clear)

        MainPanelController.configureHostingView(view)

        XCTAssertEqual(view.safeAreaRegions, [])
        XCTAssertEqual(view.layer?.cornerRadius, 40)
        XCTAssertEqual(view.layer?.cornerCurve, .continuous)
        XCTAssertEqual(view.layer?.masksToBounds, true)
    }

    @MainActor
    func testRoundedBackingLayerClipsAppKitAndBackdropContent() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 620))

        MainPanelController.configureRoundedBackingLayer(view)

        let layer = try XCTUnwrap(view.layer)
        XCTAssertEqual(layer.cornerRadius, 40)
        XCTAssertEqual(layer.cornerCurve, .continuous)
        XCTAssertTrue(layer.masksToBounds)
        XCTAssertEqual(layer.backgroundColor, NSColor.clear.cgColor)
    }

    @MainActor
    func testDraggingEveryEdgeAndCornerChangesTheWindowFrame() throws {
        let scenarios: [(String, NSPoint, NSPoint, NSRect)] = [
            ("左边", NSPoint(x: 4, y: 310), NSPoint(x: -60, y: 40),
             NSRect(x: 40, y: 100, width: 960, height: 620)),
            ("右边", NSPoint(x: 896, y: 310), NSPoint(x: 60, y: 40),
             NSRect(x: 100, y: 100, width: 960, height: 620)),
            ("下边", NSPoint(x: 450, y: 4), NSPoint(x: 60, y: -40),
             NSRect(x: 100, y: 60, width: 900, height: 660)),
            ("上边", NSPoint(x: 450, y: 616), NSPoint(x: 60, y: 40),
             NSRect(x: 100, y: 100, width: 900, height: 660)),
            ("左下角", NSPoint(x: 14, y: 14), NSPoint(x: -60, y: -40),
             NSRect(x: 40, y: 60, width: 960, height: 660)),
            ("右下角", NSPoint(x: 886, y: 14), NSPoint(x: 60, y: -40),
             NSRect(x: 100, y: 60, width: 960, height: 660)),
            ("左上角", NSPoint(x: 14, y: 606), NSPoint(x: -60, y: 40),
             NSRect(x: 40, y: 100, width: 960, height: 660)),
            ("右上角", NSPoint(x: 886, y: 606), NSPoint(x: 60, y: 40),
             NSRect(x: 100, y: 100, width: 960, height: 660))
        ]

        for (name, localStart, delta, expectedFrame) in scenarios {
            let window = makeResizeWindow()
            defer { window.orderOut(nil) }
            let start = window.convertPoint(toScreen: localStart)
            let end = NSPoint(x: start.x + delta.x, y: start.y + delta.y)

            try sendMouse(.leftMouseDown, to: window, screenPoint: start)
            try sendMouse(.leftMouseDragged, to: window, screenPoint: end)
            window.applyPendingResize()
            try sendMouse(.leftMouseUp, to: window, screenPoint: end)

            XCTAssertEqual(window.frame, expectedFrame, name)
        }
    }

    @MainActor
    func testContinuousDragUsesScreenCoordinatesWhenTheWindowOriginChanges() throws {
        let initialFrame = NSRect(x: -1200, y: -800, width: 900, height: 620)
        let window = makeResizeWindow(frame: initialFrame)
        defer { window.orderOut(nil) }
        XCTAssertEqual(window.frame, initialFrame)
        let start = window.convertPoint(toScreen: NSPoint(x: 14, y: 14))

        try sendMouse(.leftMouseDown, to: window, screenPoint: start)
        for delta in [NSPoint(x: -40, y: -30), NSPoint(x: -80, y: -60), NSPoint(x: 20, y: 15)] {
            try sendMouse(
                .leftMouseDragged,
                to: window,
                screenPoint: NSPoint(x: start.x + delta.x, y: start.y + delta.y)
            )
            window.applyPendingResize()
            XCTAssertEqual(
                window.frame,
                NSRect(
                    x: initialFrame.minX + delta.x,
                    y: initialFrame.minY + delta.y,
                    width: initialFrame.width - delta.x,
                    height: initialFrame.height - delta.y
                )
            )
            XCTAssertEqual(window.frame.maxX, initialFrame.maxX)
            XCTAssertEqual(window.frame.maxY, initialFrame.maxY)
        }
        try sendMouse(.leftMouseUp, to: window, screenPoint: NSPoint(x: start.x + 20, y: start.y + 15))
    }

    @MainActor
    func testResizeClampsToMinimumAndMaximumWithoutLosingTheOppositeCorner() throws {
        let window = makeResizeWindow()
        defer { window.orderOut(nil) }
        window.maxSize = NSSize(width: 960, height: 680)
        let start = window.convertPoint(toScreen: NSPoint(x: 14, y: 606))
        let scenarios: [(NSPoint, NSRect)] = [
            (NSPoint(x: 500, y: -500), NSRect(x: 400, y: 100, width: 600, height: 414)),
            (NSPoint(x: 20, y: -30), NSRect(x: 120, y: 100, width: 880, height: 590)),
            (NSPoint(x: -500, y: 500), NSRect(x: 40, y: 100, width: 960, height: 680)),
            (NSPoint(x: -10, y: 15), NSRect(x: 90, y: 100, width: 910, height: 635))
        ]

        try sendMouse(.leftMouseDown, to: window, screenPoint: start)
        for (delta, expectedFrame) in scenarios {
            try sendMouse(
                .leftMouseDragged,
                to: window,
                screenPoint: NSPoint(x: start.x + delta.x, y: start.y + delta.y)
            )
            window.applyPendingResize()
            XCTAssertEqual(window.frame, expectedFrame)
            XCTAssertEqual(window.frame.maxX, 1000)
            XCTAssertEqual(window.frame.minY, 100)
        }
        try sendMouse(.leftMouseUp, to: window, screenPoint: NSPoint(x: start.x - 10, y: start.y + 15))
    }

    @MainActor
    func testMouseUpHidingFocusLossAndCancellationEndTheResizeSession() throws {
        let endings: [(String, (MainPanelWindow) throws -> Void)] = [
            ("松开鼠标", { window in
                try self.sendMouse(
                    .leftMouseUp,
                    to: window,
                    screenPoint: NSPoint(x: window.frame.maxX - 4, y: window.frame.midY)
                )
            }),
            ("隐藏窗口", { $0.orderOut(nil) }),
            ("失去焦点", { $0.resignKey() }),
            ("取消操作", { $0.cancelOperation(nil) })
        ]

        for (name, endResize) in endings {
            let window = makeResizeWindow()
            defer { window.orderOut(nil) }
            let start = window.convertPoint(toScreen: NSPoint(x: 896, y: 310))
            try sendMouse(.leftMouseDown, to: window, screenPoint: start)
            try sendMouse(
                .leftMouseDragged,
                to: window,
                screenPoint: NSPoint(x: start.x + 40, y: start.y)
            )
            window.applyPendingResize()
            XCTAssertEqual(window.frame.width, 940, name)
            let frameBeforeEnding = window.frame

            try endResize(window)
            try sendMouse(
                .leftMouseDragged,
                to: window,
                screenPoint: NSPoint(x: start.x + 80, y: start.y)
            )

            window.applyPendingResize()
            XCTAssertEqual(window.frame, frameBeforeEnding, name)
            XCTAssertFalse(window.isResizeScheduled, name)
        }
    }

    @MainActor
    func testInteriorAndTransparentCornerMouseEventsAreNotConsumedByResize() throws {
        let points = [
            NSPoint(x: 450, y: 310),
            NSPoint(x: 20, y: 310),
            NSPoint(x: 450, y: 12),
            NSPoint(x: 40, y: 40),
            NSPoint(x: 2, y: 2)
        ]

        for localPoint in points {
            let window = makeResizeWindow()
            defer { window.orderOut(nil) }
            let initialFrame = window.frame
            let start = window.convertPoint(toScreen: localPoint)
            let end = NSPoint(x: start.x + 25, y: start.y + 20)

            // AppKit 不向未展示窗口的 NSView 分发鼠标事件，直接检查生产事件处理是否消费事件。
            for (type, point) in [
                (NSEvent.EventType.leftMouseDown, start),
                (.leftMouseDragged, end),
                (.leftMouseUp, end)
            ] {
                let event = try mouseEvent(type, for: window, screenPoint: point)
                XCTAssertFalse(window.handleResizeEvent(event), "\(localPoint)的内容事件应交给 AppKit")
            }

            XCTAssertEqual(window.frame, initialFrame, "\(localPoint)")
        }
    }


    @MainActor
    func testQueuedScreenEventsReturnLeftBottomAndCornerToTheirOriginalFrame() throws {
        let scenarios: [(NSPoint, [NSPoint])] = [
            (NSPoint(x: 4, y: 310), [-10, -20, -30, -20, -10, 0].map { NSPoint(x: $0, y: 0) }),
            (NSPoint(x: 450, y: 4), [-10, -20, -30, -20, -10, 0].map { NSPoint(x: 0, y: $0) }),
            (NSPoint(x: 14, y: 14), [-10, -20, -30, -20, -10, 0].map { NSPoint(x: $0, y: $0) })
        ]

        for (localStart, deltas) in scenarios {
            let window = makeResizeWindow()
            defer { window.orderOut(nil) }
            let initial = window.frame
            let start = window.convertPoint(toScreen: localStart)
            // 所有事件在处理第一帧之前生成，模拟主线程短暂繁忙时已经进入队列的鼠标事件。
            let queuedEvents = try deltas.map { delta in
                try mouseEvent(
                    .leftMouseDragged,
                    for: window,
                    screenPoint: NSPoint(x: start.x + delta.x, y: start.y + delta.y)
                )
            }

            try sendMouse(.leftMouseDown, to: window, screenPoint: start)
            for (event, delta) in zip(queuedEvents, deltas) {
                XCTAssertEqual(
                    try XCTUnwrap(event.cgEvent).unflippedLocation,
                    NSPoint(x: start.x + delta.x, y: start.y + delta.y)
                )
                window.sendEvent(event)
                window.applyPendingResize()
                XCTAssertEqual(
                    window.frame,
                    NSRect(
                        x: initial.minX + delta.x,
                        y: initial.minY + delta.y,
                        width: initial.width - delta.x,
                        height: initial.height - delta.y
                    )
                )
            }
            try sendMouse(.leftMouseUp, to: window, screenPoint: start)
            XCTAssertEqual(window.frame, initial)
        }
    }

    @MainActor
    func testBurstOfMouseEventsAppliesOnlyTheLatestSizeOnOneDisplayTick() throws {
        let window = makeResizeWindow()
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(window.contentView as? NonMovingPanelContent)
        content.sizeChanges.removeAll()
        let initial = window.frame
        let start = window.convertPoint(toScreen: NSPoint(x: 896, y: 310))
        try sendMouse(.leftMouseDown, to: window, screenPoint: start)

        for distance in 1...100 {
            try sendMouse(
                .leftMouseDragged,
                to: window,
                screenPoint: NSPoint(x: start.x + CGFloat(distance), y: start.y)
            )
        }

        XCTAssertTrue(window.isResizeScheduled)
        XCTAssertEqual(window.frame, initial)
        XCTAssertTrue(content.sizeChanges.isEmpty)
        window.applyPendingResize()
        XCTAssertEqual(window.frame.width, 1000)
        XCTAssertEqual(content.sizeChanges, [NSSize(width: 1000, height: 620)])

        window.applyPendingResize()
        window.applyPendingResize()
        XCTAssertEqual(content.sizeChanges.count, 1, "没有新鼠标位置时不能重复更新窗口")
        try sendMouse(.leftMouseUp, to: window, screenPoint: NSPoint(x: start.x + 100, y: start.y))
        XCTAssertEqual(content.sizeChanges.count, 1)
        XCTAssertFalse(window.isResizeScheduled)
    }

    @MainActor
    func testRepeatedDraggingBeyondMinimumSizeDoesNotReapplyTheSameFrame() throws {
        let window = makeResizeWindow()
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(window.contentView as? NonMovingPanelContent)
        content.sizeChanges.removeAll()
        let start = window.convertPoint(toScreen: NSPoint(x: 886, y: 606))
        try sendMouse(.leftMouseDown, to: window, screenPoint: start)

        for distance in [500, 600, 700] {
            try sendMouse(
                .leftMouseDragged,
                to: window,
                screenPoint: NSPoint(x: start.x - CGFloat(distance), y: start.y - CGFloat(distance))
            )
            window.applyPendingResize()
            XCTAssertEqual(window.frame, NSRect(x: 100, y: 100, width: 600, height: 414))
        }

        XCTAssertEqual(content.sizeChanges, [NSSize(width: 600, height: 414)])
        try sendMouse(.leftMouseUp, to: window, screenPoint: NSPoint(x: start.x - 700, y: start.y - 700))
        XCTAssertEqual(content.sizeChanges.count, 1)
    }

    @MainActor
    func testMouseUpBeforeTheDisplayTickAppliesItsFinalPointerPosition() throws {
        let window = makeResizeWindow()
        defer { window.orderOut(nil) }
        let content = try XCTUnwrap(window.contentView as? NonMovingPanelContent)
        content.sizeChanges.removeAll()
        let start = window.convertPoint(toScreen: NSPoint(x: 896, y: 310))
        try sendMouse(.leftMouseDown, to: window, screenPoint: start)
        try sendMouse(.leftMouseDragged, to: window, screenPoint: NSPoint(x: start.x + 40, y: start.y))
        XCTAssertEqual(window.frame.width, 900)

        try sendMouse(.leftMouseUp, to: window, screenPoint: NSPoint(x: start.x + 70, y: start.y))

        XCTAssertEqual(window.frame.width, 970)
        XCTAssertEqual(content.sizeChanges, [NSSize(width: 970, height: 620)])
        XCTAssertFalse(window.isResizeScheduled)
        window.applyPendingResize()
        XCTAssertEqual(window.frame.width, 970)
        XCTAssertEqual(content.sizeChanges.count, 1)
    }

    @MainActor
    func testCancellationDiscardsPendingFramesAndIgnoresLateTicksAndMouseEvents() throws {
        let cancellations: [(String, (MainPanelWindow) -> Void)] = [
            ("隐藏窗口", { $0.orderOut(nil) }),
            ("失去焦点", { $0.resignKey() }),
            ("取消操作", { $0.cancelOperation(nil) })
        ]
        for (name, cancel) in cancellations {
            let window = makeResizeWindow()
            defer { window.orderOut(nil) }
            let content = try XCTUnwrap(window.contentView as? NonMovingPanelContent)
            content.sizeChanges.removeAll()
            let initial = window.frame
            let start = window.convertPoint(toScreen: NSPoint(x: 896, y: 310))
            try sendMouse(.leftMouseDown, to: window, screenPoint: start)
            try sendMouse(.leftMouseDragged, to: window, screenPoint: NSPoint(x: start.x + 40, y: start.y))
            XCTAssertTrue(window.isResizeScheduled, name)

            cancel(window)
            window.applyPendingResize()
            try sendMouse(.leftMouseDragged, to: window, screenPoint: NSPoint(x: start.x + 80, y: start.y))
            try sendMouse(.leftMouseUp, to: window, screenPoint: NSPoint(x: start.x + 90, y: start.y))
            window.applyPendingResize()

            XCTAssertEqual(window.frame, initial, name)
            XCTAssertTrue(content.sizeChanges.isEmpty, name)
            XCTAssertFalse(window.isResizeScheduled, name)
        }
    }

    @MainActor
    func testAnActiveResizeDoesNotRetainItsWindow() throws {
        weak var releasedWindow: MainPanelWindow?
        try autoreleasepool {
            let window = makeResizeWindow()
            releasedWindow = window
            let start = window.convertPoint(toScreen: NSPoint(x: 896, y: 310))
            try sendMouse(.leftMouseDown, to: window, screenPoint: start)
            try sendMouse(.leftMouseDragged, to: window, screenPoint: NSPoint(x: start.x + 40, y: start.y))
            XCTAssertTrue(window.isResizeScheduled)
        }
        XCTAssertNil(releasedWindow, "显示刷新回调不能强持有已释放的面板")
    }

    @MainActor
    private func makeResizeWindow(
        frame: NSRect = NSRect(x: 100, y: 100, width: 900, height: 620)
    ) -> MainPanelWindow {
        _ = NSApplication.shared
        let window = MainPanelWindow(
            contentRect: frame,
            styleMask: MainPanelController.windowStyleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.hasShadow = MainPanelController.usesSystemWindowShadow
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 600, height: 414)
        window.isMovableByWindowBackground = true
        let content = NonMovingPanelContent(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = content
        MainPanelController.configureRoundedBackingLayer(content)
        if let frameView = content.superview {
            MainPanelController.configureRoundedBackingLayer(frameView)
        }
        window.setFrame(frame, display: false)
        return window
    }

    @MainActor
    private func sendMouse(
        _ type: NSEvent.EventType,
        to window: NSWindow,
        screenPoint: NSPoint
    ) throws {
        window.sendEvent(try mouseEvent(type, for: window, screenPoint: screenPoint))
    }

    @MainActor
    private func mouseEvent(
        _ type: NSEvent.EventType,
        for window: NSWindow,
        screenPoint: NSPoint
    ) throws -> NSEvent {
        let source = try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: window.convertPoint(fromScreen: screenPoint),
            modifierFlags: [],
            timestamp: 1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
        // 冻结生成时的屏幕位置；直接保留 mouseEvent 会随之后的窗口位置重新计算 CGEvent 坐标。
        let snapshot = try XCTUnwrap(source.cgEvent?.copy())
        return try XCTUnwrap(NSEvent(cgEvent: snapshot))
    }
}

@MainActor
private final class NonMovingPanelContent: NSView {
    var sizeChanges: [NSSize] = []

    override var mouseDownCanMoveWindow: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { sizeChanges.append(newSize) }
        super.setFrameSize(newSize)
    }
}
