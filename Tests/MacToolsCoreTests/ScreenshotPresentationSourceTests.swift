import Foundation
import XCTest

final class ScreenshotPresentationSourceTests: XCTestCase {
    func testScreenCaptureExcludesCurrentProcessByProcessIdentifier() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/SystemScreenCaptureService.swift"
        )

        XCTAssertTrue(source.contains("application.processID == ProcessInfo.processInfo.processIdentifier"))
    }

    func testScreenCaptureUsesTopLeftDisplaySourceCoordinates() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/SystemScreenCaptureService.swift"
        )

        XCTAssertTrue(source.contains("selection.screenCaptureKitSourceFrame"))
        XCTAssertFalse(source.contains("selection.displayRelativeFrame"))
    }

    func testScreenshotEditorReusesSelectionPanelWithoutSecondDimLayerOrApplicationActivation() throws {
        let controllerSource = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenshotEditorPanelController.swift"
        )
        let coordinatorSource = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift"
        )
        let overlaySource = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift"
        )
        let editorViewSource = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenshotEditorView.swift"
        )

        let presentationStart = try XCTUnwrap(
            overlaySource.range(of: "func presentEditor(")
        )
        let nextFunction = try XCTUnwrap(
            overlaySource.range(
                of: "private func prepareForNewSelection",
                range: presentationStart.upperBound..<overlaySource.endIndex
            )
        )
        let presentationBlock = overlaySource[presentationStart.lowerBound..<nextFunction.lowerBound]
        let attaching = try XCTUnwrap(
            presentationBlock.range(of: "selectionView.presentEditor(")
        )
        let allowingKey = try XCTUnwrap(
            presentationBlock.range(of: "panel.allowsKeyWindow = true")
        )
        let keying = try XCTUnwrap(
            presentationBlock.range(of: "panel.makeKey()")
        )

        XCTAssertLessThan(attaching.lowerBound, allowingKey.lowerBound)
        XCTAssertLessThan(allowingKey.lowerBound, keying.lowerBound)
        XCTAssertFalse(presentationBlock.contains("orderFront"))
        XCTAssertFalse(presentationBlock.contains("NSApp.activate"))
        XCTAssertFalse(controllerSource.contains("NSPanel("))
        XCTAssertFalse(controllerSource.contains("NSApp.activate"))
        XCTAssertFalse(controllerSource.contains("orderFront"))
        XCTAssertFalse(editorViewSource.contains("Color.black.opacity(0.42)"))
        XCTAssertTrue(controllerSource.contains("func prepare("))
        XCTAssertTrue(controllerSource.contains("func preparedContentView()"))
        XCTAssertTrue(overlaySource.contains("styleMask: [.borderless, .nonactivatingPanel]"))
        XCTAssertTrue(overlaySource.contains("override var canBecomeKey: Bool { allowsKeyWindow }"))
        XCTAssertTrue(presentationBlock.contains("panel.isKeyWindow"))
        XCTAssertTrue(coordinatorSource.contains("editor.prepare("))
        XCTAssertTrue(coordinatorSource.contains("editor.preparedContentView()"))
        XCTAssertTrue(coordinatorSource.contains("overlay.presentEditor("))
        XCTAssertFalse(coordinatorSource.contains("editor.presentPrepared"))
    }

    func testSelectionOverlayStaysVisibleAndLocksAfterSubmission() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenSelectionOverlayController.swift"
        )
        let submissionStart = try XCTUnwrap(source.range(of: "selectionView.onDragFinished"))
        let panelStart = try XCTUnwrap(
            source.range(of: "let panel = ScreenSelectionPanel", range: submissionStart.upperBound..<source.endIndex)
        )
        let submissionBlock = source[submissionStart.lowerBound..<panelStart.lowerBound]
        let locking = try XCTUnwrap(submissionBlock.range(of: "lockSelectionInteraction()"))
        let handling = try XCTUnwrap(submissionBlock.range(of: "handler(selection, mode)"))

        XCTAssertTrue(source.contains("isSelectionCommitted"))
        XCTAssertTrue(source.contains("lockSelectionInteraction()"))
        XCTAssertTrue(source.contains("isInteractionLocked = true"))
        XCTAssertFalse(submissionBlock.contains("dismiss()"))
        XCTAssertLessThan(locking.lowerBound, handling.lowerBound)
    }

    func testScreenTopologyChangeInvalidatesCacheAndMissingDisplayRetriesOnce() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/SystemScreenCaptureService.swift"
        )

        XCTAssertTrue(source.contains("NSApplication.didChangeScreenParametersNotification"))
        XCTAssertTrue(source.contains("retryAfterRefresh: false"))
        XCTAssertTrue(source.contains("guard retryAfterRefresh"))
    }

    func testPendingCaptureCancellationDiscardsLateScreenshotAndRecordingResults() throws {
        let source = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift"
        )

        XCTAssertTrue(source.contains("!isCancelled else"))
        XCTAssertTrue(source.contains("self.sessionGeneration == sessionGeneration"))
        XCTAssertTrue(source.contains("_ = try? await recorder.stop()"))
        XCTAssertTrue(source.contains("try? FileManager.default.removeItem(at: destination)"))
    }

    private func sourceFile(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}
