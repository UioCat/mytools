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

    func testScreenshotEditorActivatesAccessoryAppBeforeOrderingPanelFront() throws {
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

        XCTAssertLessThan(activation.lowerBound, ordering.lowerBound)
        XCTAssertFalse(controllerSource.contains("panel.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(controllerSource.contains("return panel.isVisible"))
        XCTAssertTrue(coordinatorSource.contains("guard editor.present("))
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
