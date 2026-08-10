import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import MacToolsCore

final class ScreenshotEditorInteractionTests: XCTestCase {
    @MainActor
    func testFocusedTextEditorConsumesCommandsAndIMEscapeBeforeScreenshotActions() throws {
        let rootSize = CGSize(width: 800, height: 600)
        let imageFrame = CGRect(x: 200, y: 100, width: 400, height: 300)
        let toolbarFrame = CGRect(x: 162, y: 450, width: 476, height: 68)
        let toolbarMeasurement = ScreenshotCompactToolbarMeasurementSink()
        var copyCount = 0
        var registeredEscapeHandler: ((Bool) -> ScreenshotEditorEscapeAction)?
        let editor = ScreenshotEditorView(
            image: try makeSolidImage(width: 400, height: 300),
            imageFrame: imageFrame,
            toolbarFrame: toolbarFrame,
            settings: .defaults,
            onSettingsChange: { _ in true },
            onCopy: { _ in copyCount += 1 },
            onCancel: {},
            registerEscapeHandler: { registeredEscapeHandler = $0 },
            clearEscapeHandler: {}
        )
        .environment(\.screenshotCompactToolbarMeasurement, toolbarMeasurement)
        .frame(width: rootSize.width, height: rootSize.height)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: rootSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: editor)
        hostingView.frame = CGRect(origin: .zero, size: rootSize)
        window.contentView = hostingView
        ScreenshotEditorTestWindowRetainer.windows.append(window)
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
        }
        runMainLoop()

        let textToolFrame = try XCTUnwrap(toolbarMeasurement.frames["tool-text"])
        sendClick(
            to: window,
            swiftUIPoint: compactControlCenter(
                textToolFrame,
                toolbarFrame: toolbarFrame
            ),
            rootHeight: rootSize.height
        )
        sendClick(
            to: window,
            swiftUIPoint: CGPoint(x: imageFrame.midX, y: imageFrame.midY),
            rootHeight: rootSize.height
        )
        runMainLoop()

        let textView = try XCTUnwrap(window.firstResponder as? NSTextView)
        sendKey(to: window, keyCode: 0, characters: "a")
        XCTAssertEqual(textView.string, "a")

        XCTAssertEqual(
            ScreenshotEditorKeyEventRouter.route(
                event: try keyEvent(
                    for: window,
                    keyCode: 6,
                    characters: "z",
                    modifiers: .command
                ),
                firstResponder: window.firstResponder,
                handler: try XCTUnwrap(registeredEscapeHandler)
            ),
            .consumed
        )
        runMainLoop()
        XCTAssertEqual(textView.string, "")

        sendKey(to: window, keyCode: 7, characters: "x")
        XCTAssertEqual(
            ScreenshotEditorKeyEventRouter.route(
                event: try keyEvent(
                    for: window,
                    keyCode: 6,
                    characters: "z",
                    modifiers: [.command, .capsLock]
                ),
                firstResponder: window.firstResponder,
                handler: try XCTUnwrap(registeredEscapeHandler)
            ),
            .consumed
        )
        runMainLoop()
        XCTAssertEqual(textView.string, "")

        sendKey(to: window, keyCode: 11, characters: "b")
        sendKey(to: window, keyCode: 51, characters: "\u{7F}")
        XCTAssertEqual(textView.string, "")

        sendKey(to: window, keyCode: 8, characters: "c")
        XCTAssertEqual(
            ScreenshotEditorKeyEventRouter.route(
                event: try keyEvent(
                    for: window,
                    keyCode: 36,
                    characters: "\r",
                    modifiers: .command
                ),
                firstResponder: window.firstResponder,
                handler: try XCTUnwrap(registeredEscapeHandler)
            ),
            .consumed
        )
        runMainLoop()
        XCTAssertEqual(copyCount, 0)
        XCTAssertTrue(window.firstResponder === textView)
        XCTAssertEqual(
            ScreenshotEditorKeyEventRouter.route(
                event: try keyEvent(
                    for: window,
                    keyCode: 76,
                    characters: "\r",
                    modifiers: [.command, .numericPad]
                ),
                firstResponder: window.firstResponder,
                handler: try XCTUnwrap(registeredEscapeHandler)
            ),
            .consumed
        )
        runMainLoop()
        XCTAssertEqual(textView.string, "c\n\n")
        XCTAssertEqual(copyCount, 0)
        XCTAssertTrue(window.firstResponder === textView)

        textView.setMarkedText(
            "拼",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        let escapeHandler = try XCTUnwrap(registeredEscapeHandler)
        XCTAssertEqual(
            ScreenshotEditorKeyEventRouter.route(
                event: try keyEvent(
                    for: window,
                    keyCode: 53,
                    characters: "\u{1B}"
                ),
                firstResponder: window.firstResponder,
                handler: escapeHandler
            ),
            .forwardToResponder
        )

        textView.unmarkText()
        XCTAssertEqual(
            ScreenshotEditorKeyEventRouter.route(
                event: try keyEvent(
                    for: window,
                    keyCode: 53,
                    characters: "\u{1B}"
                ),
                firstResponder: window.firstResponder,
                handler: escapeHandler
            ),
            .consumed
        )
        XCTAssertEqual(copyCount, 0)
    }

    private func compactControlCenter(
        _ frame: CGRect,
        toolbarFrame: CGRect
    ) -> CGPoint {
        let layoutWidth = ScreenCaptureEditorToolbarMetrics.contentWidth(controlCount: 11)
        let layoutHeight = ScreenCaptureEditorToolbarMetrics.controlSize
            + ScreenCaptureEditorToolbarMetrics.compactPadding * 2
        return CGPoint(
            x: toolbarFrame.minX + (toolbarFrame.width - layoutWidth) / 2 + frame.midX,
            y: toolbarFrame.minY + (toolbarFrame.height - layoutHeight) / 2 + frame.midY
        )
    }

    @MainActor
    private func sendClick(
        to window: NSWindow,
        swiftUIPoint: CGPoint,
        rootHeight: CGFloat
    ) {
        let location = CGPoint(x: swiftUIPoint.x, y: rootHeight - swiftUIPoint.y)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: location,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )
        let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: location,
            modifierFlags: [],
            timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        )
        if let mouseDown {
            window.sendEvent(mouseDown)
        }
        if let mouseUp {
            window.sendEvent(mouseUp)
        }
        runMainLoop()
    }

    @MainActor
    private func sendKey(
        to window: NSWindow,
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        for eventType in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: eventType,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ) {
                window.sendEvent(event)
            }
        }
        runMainLoop()
    }

    @MainActor
    private func keyEvent(
        for window: NSWindow,
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    @MainActor
    private func runMainLoop() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
    }

    private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
private enum ScreenshotEditorTestWindowRetainer {
    static var windows: [NSWindow] = []
}
