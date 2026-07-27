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

    func testScreenshotEditorPreparesBeforeReplacingSelectionOverlay() throws {
        let controllerSource = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenshotEditorPanelController.swift"
        )
        let coordinatorSource = try sourceFile(
            "Sources/MacTools/App/ScreenCapture/ScreenCaptureCoordinator.swift"
        )

        let activation = try XCTUnwrap(
            controllerSource.range(of: "NSApp.activate(ignoringOtherApps: true)")
        )
        let ordering = try XCTUnwrap(
            controllerSource.range(of: "panel.orderFrontRegardless()")
        )
        let replacing = try XCTUnwrap(
            controllerSource.range(of: "replaceVisibleSurface()")
        )
        let keying = try XCTUnwrap(
            controllerSource.range(of: "panel.makeKey()")
        )

        XCTAssertLessThan(activation.lowerBound, ordering.lowerBound)
        XCTAssertLessThan(ordering.lowerBound, replacing.lowerBound)
        XCTAssertLessThan(replacing.lowerBound, keying.lowerBound)
        XCTAssertFalse(controllerSource.contains("panel.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(controllerSource.contains("func prepare("))
        XCTAssertTrue(controllerSource.contains("func presentPrepared("))
        XCTAssertTrue(coordinatorSource.contains("editor.prepare("))
        XCTAssertTrue(coordinatorSource.contains("editor.presentPrepared"))
        XCTAssertTrue(coordinatorSource.contains("self?.overlay.dismiss()"))
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
