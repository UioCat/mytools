import Foundation
import XCTest

final class ScreenshotPresentationSourceTests: XCTestCase {
    func testScreenCaptureExcludesCurrentProcessByProcessIdentifier() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/SystemScreenCaptureService.swift"
        )

        XCTAssertTrue(source.contains("application.processID == ProcessInfo.processInfo.processIdentifier"))
    }

    func testScreenCaptureUsesTopLeftDisplaySourceCoordinates() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/SystemScreenCaptureService.swift"
        )

        XCTAssertTrue(source.contains("selection.screenCaptureKitSourceFrame"))
        XCTAssertFalse(source.contains("selection.displayRelativeFrame"))
    }

    func testScreenshotEditorReusesSelectionPanelWithoutSecondDimLayerOrApplicationActivation() throws {
        let controllerSource = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenshotEditorPanelController.swift"
        )
        let coordinatorSource = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenCaptureCoordinator.swift"
        )
        let overlaySource = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenSelectionOverlayController.swift"
        )
        let editorViewSource = try sourceFile(
            "Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorView.swift"
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
            "Sources/MacTools/Platform/ScreenCapture/ScreenSelectionOverlayController.swift"
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

    func testCaptureModeToolbarUsesSharedSwiftUILiquidGlassSurface() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenSelectionOverlayController.swift"
        )

        XCTAssertTrue(source.contains("NSHostingView("))
        XCTAssertTrue(source.contains("CaptureModeToolbarView"))
        XCTAssertTrue(source.contains(".liquidGlassPanel("))
        XCTAssertTrue(source.contains(".liquidGlassInteractionSurface("))
        XCTAssertFalse(source.contains("NSSegmentedControl"))
        XCTAssertFalse(source.contains("NSVisualEffectView"))
    }

    func testScreenshotEditorUsesResponsiveSingleRowToolbarAndExclusiveParameterPopovers() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorView.swift"
        )

        XCTAssertTrue(source.contains("ScreenCaptureEditorToolbarMetrics.ultraCompactBreakpoint"))
        XCTAssertTrue(source.contains("ScreenCaptureEditorToolbarMetrics.compactBreakpoint"))
        XCTAssertTrue(source.contains("ScreenCaptureCompactToolbarLayout"))
        XCTAssertTrue(source.contains("drawingToolMenu"))
        XCTAssertTrue(source.contains("ScreenshotEditorParameterPopover"))
        XCTAssertTrue(source.contains("parameterPopoverBinding(.color)"))
        XCTAssertTrue(source.contains("parameterPopoverBinding(.lineWidth)"))
        XCTAssertTrue(source.contains("parameterPopoverBinding(.fontSize)"))
        XCTAssertTrue(source.contains("parameterPopoverBinding(.style)"))
        XCTAssertTrue(source.contains(".liquidGlassPanel("))
        XCTAssertFalse(source.contains(".buttonStyle(.bordered)"))
        XCTAssertFalse(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertFalse(source.contains(".ultraThinMaterial"))
        XCTAssertFalse(source.contains(".thinMaterial"))
    }

    func testScreenshotEditorRoutesEscapeByEditingPhaseBeforeCancellingSession() throws {
        let overlaySource = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenSelectionOverlayController.swift"
        )
        let controllerSource = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenshotEditorPanelController.swift"
        )
        let editorSource = try sourceFile(
            "Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorView.swift"
        )
        let routerSource = try sourceFile(
            "Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorKeyEventRouter.swift"
        )

        let presentationStart = try XCTUnwrap(overlaySource.range(of: "func presentEditor("))
        let presentationEnd = try XCTUnwrap(
            overlaySource.range(
                of: "private func prepareForNewSelection",
                range: presentationStart.upperBound..<overlaySource.endIndex
            )
        )
        let presentationBlock = overlaySource[presentationStart.lowerBound..<presentationEnd.lowerBound]
        XCTAssertTrue(routerSource.contains("textView?.hasMarkedText() == true"))
        XCTAssertTrue(routerSource.contains("textView.undoManager?.undo()"))
        XCTAssertTrue(routerSource.contains("textView.insertNewline(nil)"))
        XCTAssertTrue(overlaySource.contains("ScreenshotEditorKeyEventRouter.route("))
        XCTAssertTrue(overlaySource.contains("case .forwardToResponder:"))
        XCTAssertTrue(presentationBlock.contains("NSEvent.removeMonitor(globalEscapeEventMonitor)"))
        XCTAssertTrue(controllerSource.contains("func handleEscape(hasMarkedText: Bool)"))
        XCTAssertTrue(editorSource.contains("private func handleEscape(hasMarkedText: Bool)"))
        XCTAssertTrue(editorSource.contains("ScreenshotEditorEscapePolicy.action("))
    }

    func testLabelPreviewAndEditorUseSharedReadableStyle() throws {
        let source = try sourceFile(
            "Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorView.swift"
        )

        XCTAssertTrue(
            source.contains(
                ".font(.system(size: canvasLineWidth(fontSize, in: imageRect), weight: .medium))"
            )
        )
        XCTAssertTrue(source.contains("ScreenshotLabelTextField("))
        XCTAssertTrue(source.contains("editor.textContainer?.lineFragmentPadding = 0"))
        XCTAssertTrue(source.contains("field.alignment = .center"))
        XCTAssertTrue(source.contains("labelColor(ScreenshotLabelStyle.backgroundColor)"))
        XCTAssertTrue(source.contains("labelColor(ScreenshotLabelStyle.foregroundColor)"))
        XCTAssertTrue(source.contains("ScreenshotLabelStyle.maximumBubbleWidth("))
        XCTAssertTrue(source.contains("ScreenshotLabelStyle.resolvedMaximumBubbleWidth("))
        XCTAssertTrue(source.contains("labelFontSize: annotationFontSize.points"))
        XCTAssertFalse(source.contains("Color(red: 0.09, green: 0.10, blue: 0.12)"))
        XCTAssertFalse(source.contains("min(240 * scale"))
    }

    func testPlainLiquidGlassButtonsUseTheSharedFullSurfaceHitTarget() throws {
        let surfaceSource = try sourceFile(
            "Sources/MacToolsCore/UI/DesignSystem/LiquidGlassSurface.swift"
        )
        let overlaySource = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenSelectionOverlayController.swift"
        )
        let editorSource = try sourceFile(
            "Sources/MacToolsCore/UI/ScreenCapture/ScreenshotEditorView.swift"
        )
        let runtimeSource = try sourceFile(
            "Sources/MacTools/Application/RuntimeViews.swift"
        )
        let themeSource = try sourceFile(
            "Sources/MacToolsCore/UI/DesignSystem/MacToolsGlassTheme.swift"
        )
        let mainPanelSource = try sourceFile(
            "Sources/MacToolsCore/UI/Clipboard/MainPanelView.swift"
        )
        let contextPanelSource = try sourceFile(
            "Sources/MacToolsCore/UI/SuperRightClick/ContextActionView.swift"
        )

        XCTAssertTrue(surfaceSource.contains("func liquidGlassButtonHitTarget("))
        XCTAssertTrue(surfaceSource.contains("contentShape(\n            .interaction,"))
        XCTAssertGreaterThanOrEqual(
            surfaceSource.components(separatedBy: ".liquidGlassButtonHitTarget(").count - 1,
            1
        )
        XCTAssertTrue(themeSource.contains(".liquidGlassButtonHitTarget("))
        XCTAssertTrue(mainPanelSource.contains(".liquidGlassButtonHitTarget("))
        XCTAssertTrue(contextPanelSource.contains(".liquidGlassButtonHitTarget("))
        XCTAssertTrue(overlaySource.contains(".liquidGlassButtonHitTarget("))
        XCTAssertGreaterThanOrEqual(
            editorSource.components(separatedBy: ".liquidGlassButtonHitTarget(").count - 1,
            4
        )
        XCTAssertTrue(runtimeSource.contains(".liquidGlassButtonHitTarget("))
    }

    func testScreenTopologyChangeInvalidatesCacheAndMissingDisplayRetriesOnce() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/SystemScreenCaptureService.swift"
        )

        XCTAssertTrue(source.contains("NSApplication.didChangeScreenParametersNotification"))
        XCTAssertTrue(source.contains("retryAfterRefresh: false"))
        XCTAssertTrue(source.contains("guard retryAfterRefresh"))
    }

    func testPendingCaptureCancellationDiscardsLateScreenshotAndRecordingResults() throws {
        let source = try sourceFile(
            "Sources/MacTools/Platform/ScreenCapture/ScreenCaptureCoordinator.swift"
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
