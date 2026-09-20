import AppKit
import MacToolsCore
import XCTest
@testable import MacTools

final class ContextPanelInteractionTests: XCTestCase {
    @MainActor
    func testVisibleNativePanelIgnoresOldClickAndDismissesOnlyNewOutsideClick() throws {
        _ = NSApplication.shared
        let logger = Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let controller = ContextPanelController(
            fileActionService: FileActionService(workspace: SystemWorkspaceOpening()),
            pasteboard: SystemWritablePasteboard(), windowLayoutService: SystemWindowLayoutService(logger: logger),
            windowLayoutButtons: { [] }, speechController: TranslationSpeechController(engine: SilentSpeech()), logger: logger)
        defer { controller.cancelInteraction() }
        let id = UUID()
        controller.beginInteraction(id: id, at: 10)
        controller.showText(originalText: "Synthetic panel regression", translation: nil, isTranslationLoading: true)
        let panel = try XCTUnwrap(Mirror(reflecting: controller).children.first { $0.label == "panel" }?.value as? NSPanel)
        XCTAssertTrue(panel.isVisible)
        let outside = NSPoint(x: panel.frame.maxX + 20, y: panel.frame.maxY + 20)
        controller.hideIfClickIsOutsidePanel(eventScreenLocation: outside, timestamp: 9.9)
        controller.hideIfClickIsOutsidePanel(eventScreenLocation: outside, timestamp: 10.0009)
        XCTAssertTrue(panel.isVisible, "Queued trigger/previous-click events cannot hide a new panel")
        controller.hideIfClickIsOutsidePanel(eventScreenLocation: NSPoint(x: panel.frame.midX, y: panel.frame.midY), timestamp: 10.1)
        XCTAssertTrue(panel.isVisible)
        controller.hideIfClickIsOutsidePanel(eventScreenLocation: outside, timestamp: 10.2)
        XCTAssertFalse(panel.isVisible)
        XCTAssertFalse(controller.acceptsResult(for: id), "A late translation or Finder completion cannot reopen this session")
    }

    @MainActor
    func testGlobalClickCoordinatesUseEventLocationInsteadOfCurrentPointer() throws {
        let primary = try XCTUnwrap(NSScreen.screens.first)
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: -120, y: 200), mouseButton: .left))
        let appKitEvent = try XCTUnwrap(NSEvent(cgEvent: event))
        XCTAssertEqual(ContextPanelController.screenLocation(for: appKitEvent),
                       NSPoint(x: -120, y: primary.frame.maxY - 200))
    }

    @MainActor
    func testOutsideClickCancelsPendingCaptureBeforePanelExists() {
        let logger = Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let controller = ContextPanelController(
            fileActionService: FileActionService(workspace: SystemWorkspaceOpening()),
            pasteboard: SystemWritablePasteboard(), windowLayoutService: SystemWindowLayoutService(logger: logger),
            windowLayoutButtons: { [] }, speechController: TranslationSpeechController(engine: SilentSpeech()), logger: logger)
        let id = UUID()
        var cancelled = 0
        controller.onDismiss = { cancelled += 1 }
        controller.beginInteraction(id: id, at: 10)
        controller.hideIfClickIsOutsidePanel(eventScreenLocation: .zero, timestamp: 10.1)
        XCTAssertFalse(controller.acceptsResult(for: id))
        XCTAssertEqual(cancelled, 1)
    }
}

@MainActor
private final class SilentSpeech: TranslationSpeechEngine {
    func speak(_ request: TranslationSpeechRequest, completion: @escaping TranslationSpeechCompletion) {}
    func stop() {}
}
