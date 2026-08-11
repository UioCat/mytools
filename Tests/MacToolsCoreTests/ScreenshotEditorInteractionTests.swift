import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import MacToolsCore

final class ScreenshotEditorInteractionTests: XCTestCase {
    func testEditingDraftStyleUpdateRecoversOversizedTextAndPreservesFailureRollback() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        let textContentBounds = imageBounds.insetBy(dx: 8, dy: 8)
        let draft = ScreenshotTextDraft(
            id: nil,
            kind: .text,
            text: "一\n二\n三\n四\n五",
            frame: CGRect(x: 40, y: 64, width: 48, height: 48),
            anchor: .zero,
            direction: .left,
            color: .blue,
            fontSize: 24,
            maximumWidth: textContentBounds.width
        )

        XCTAssertNil(
            draft.updatingStyle(
                fontSize: 24,
                imageBounds: imageBounds,
                textContentBounds: textContentBounds,
                imageWidth: imageBounds.width,
                scale: 1
            )
        )
        let recovered = try XCTUnwrap(
            draft.updatingStyle(
                color: .red,
                fontSize: 12,
                imageBounds: imageBounds,
                textContentBounds: textContentBounds,
                imageWidth: imageBounds.width,
                scale: 1
            )
        )
        XCTAssertEqual(recovered.color, .red)
        XCTAssertEqual(recovered.fontSize, 12)
        XCTAssertTrue(textContentBounds.contains(recovered.frame))
        XCTAssertLessThan(recovered.frame.height, textContentBounds.height)
        XCTAssertEqual(draft.color, .blue)
        XCTAssertEqual(draft.fontSize, 24)
    }

    func testEditingLabelStyleUpdateKeepsResizedGeometryInsideImage() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 400, height: 160)
        let draft = ScreenshotTextDraft(
            id: nil,
            kind: .label,
            text: "边缘标签",
            frame: .zero,
            anchor: CGPoint(x: 390, y: 80),
            direction: .left,
            color: .blue,
            fontSize: 12,
            maximumWidth: 180
        )
        let updated = try XCTUnwrap(
            draft.updatingStyle(
                color: .orange,
                fontSize: 24,
                imageBounds: imageBounds,
                textContentBounds: imageBounds.insetBy(dx: 8, dy: 8),
                imageWidth: imageBounds.width,
                scale: 1
            )
        )
        let geometry = ScreenshotTextLayout.labelGeometry(
            text: updated.text,
            anchor: updated.anchor,
            direction: updated.direction,
            fontSize: updated.fontSize,
            maximumWidth: updated.maximumWidth
        )

        XCTAssertEqual(updated.color, .orange)
        XCTAssertEqual(updated.fontSize, 24)
        XCTAssertTrue(imageBounds.contains(geometry.bounds))
    }

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

    @MainActor
    func testLabelEditorAcceptsShortTextInProductionView() throws {
        let rootSize = CGSize(width: 800, height: 600)
        let imageFrame = CGRect(x: 200, y: 100, width: 400, height: 300)
        let toolbarFrame = CGRect(x: 162, y: 450, width: 476, height: 68)
        let toolbarMeasurement = ScreenshotCompactToolbarMeasurementSink()
        let editor = ScreenshotEditorView(
            image: try makeSplitImage(width: 400, height: 300),
            imageFrame: imageFrame,
            toolbarFrame: toolbarFrame,
            settings: .defaults,
            onSettingsChange: { _ in true },
            onCopy: { _ in },
            onCancel: {},
            registerEscapeHandler: { _ in },
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

        let labelToolFrame = try XCTUnwrap(toolbarMeasurement.frames["tool-label"])
        sendClick(
            to: window,
            swiftUIPoint: compactControlCenter(labelToolFrame, toolbarFrame: toolbarFrame),
            rootHeight: rootSize.height
        )
        sendClick(
            to: window,
            swiftUIPoint: CGPoint(x: imageFrame.minX + 100, y: imageFrame.midY),
            rootHeight: rootSize.height
        )
        runMainLoop()

        let textView = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(textView.textContainerInset, .zero)
        XCTAssertEqual(try XCTUnwrap(textView.textContainer).lineFragmentPadding, 0)
        XCTAssertEqual(textView.alignment, .center)
        textView.insertText(
            "hello",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        XCTAssertEqual(textView.string, "hello")
        let textContainer = try XCTUnwrap(textView.textContainer)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let glyphBounds = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        XCTAssertGreaterThanOrEqual(glyphBounds.minX, 0)
        XCTAssertLessThanOrEqual(glyphBounds.maxX, textContainer.containerSize.width)
        XCTAssertEqual(
            glyphBounds.midX,
            textContainer.containerSize.width / 2,
            accuracy: 1
        )
        let contentView = try XCTUnwrap(window.contentView)
        let labelField = try XCTUnwrap(
            textField(using: textView, below: contentView)
        )
        let glyphCenterInEditor = CGPoint(
            x: glyphBounds.midX + textView.textContainerOrigin.x,
            y: glyphBounds.midY + textView.textContainerOrigin.y
        )
        let glyphCenterInField = textView.convert(glyphCenterInEditor, to: labelField)
        XCTAssertEqual(glyphCenterInField.y, labelField.bounds.midY, accuracy: 1)

        textView.selectAll(nil)
        textView.insertText(
            "gekki word 我 是 ",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        let prefixLabelEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        prefixLabelEditor.setMarkedText(
            "333",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        let markedLabelEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        let markedLabelField = try XCTUnwrap(
            textField(using: markedLabelEditor, below: contentView)
        )
        let expectedMarkedLabelWidth = ceil(
            ScreenshotTextLayout.singleLineWidth(
                text: "gekki word 我 是 333",
                fontSize: 16
            ) + ScreenshotLabelStyle.glyphSafetyWidth(for: 16)
        )
        XCTAssertEqual(markedLabelEditor.string, "gekki word 我 是 333")
        XCTAssertTrue(markedLabelEditor.hasMarkedText())
        XCTAssertGreaterThanOrEqual(
            markedLabelField.bounds.width,
            expectedMarkedLabelWidth
        )

        markedLabelEditor.unmarkText()
        let longText = "hello, 大家好，这是一个需要完整展开的标签文本"
        markedLabelEditor.selectAll(nil)
        markedLabelEditor.insertText(
            longText,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        sendKey(to: window, keyCode: 36, characters: "\r")
        runMainLoop()

        let committedLabel = try XCTUnwrap(
            textField(with: longText, editable: false, below: contentView)
        )
        XCTAssertGreaterThan(committedLabel.bounds.width, 240)
    }

    @MainActor
    func testPlainTextEditorCentersShortContentAndHugsCommittedTextInProductionEditor() throws {
        let rootSize = CGSize(width: 800, height: 600)
        let imageFrame = CGRect(x: 200, y: 100, width: 400, height: 300)
        let toolbarFrame = CGRect(x: 162, y: 450, width: 476, height: 68)
        let toolbarMeasurement = ScreenshotCompactToolbarMeasurementSink()
        let editor = ScreenshotEditorView(
            image: try makeSolidImage(width: 400, height: 300),
            imageFrame: imageFrame,
            toolbarFrame: toolbarFrame,
            settings: ScreenCaptureSettings(
                annotationTool: .text,
                annotationFontSize: .large
            ),
            onSettingsChange: { _ in true },
            onCopy: { _ in },
            onCancel: {},
            registerEscapeHandler: { _ in },
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
            swiftUIPoint: compactControlCenter(textToolFrame, toolbarFrame: toolbarFrame),
            rootHeight: rootSize.height
        )
        sendClick(
            to: window,
            swiftUIPoint: CGPoint(x: imageFrame.minX + 100, y: imageFrame.midY),
            rootHeight: rootSize.height
        )
        runMainLoop()

        let textView = try XCTUnwrap(
            window.firstResponder as? ScreenshotPlainTextEditorTextView
        )
        let editorFont = try XCTUnwrap(textView.font)
        let interactionView = try XCTUnwrap(textView.superview)
        let placeholderTextView = try XCTUnwrap(
            interactionView.subviews
                .compactMap { $0 as? NSTextView }
                .first { $0 !== textView },
            "占位必须通过独立但配置相同的 NSTextView/TextKit 链路绘制"
        )
        let placeholderFont = try XCTUnwrap(placeholderTextView.font)
        XCTAssertEqual(editorFont.pointSize, ScreenshotAnnotationFontSize.large.points)
        XCTAssertEqual(placeholderFont.pointSize, editorFont.pointSize, accuracy: 0.1)
        XCTAssertEqual(placeholderFont.fontName, editorFont.fontName)
        XCTAssertEqual(placeholderTextView.string, "输入文本")
        XCTAssertTrue(textView.isPlaceholderVisible)
        XCTAssertFalse(placeholderTextView.isHidden)
        XCTAssertEqual(textView.accessibilityPlaceholderValue(), "输入文本")
        XCTAssertEqual(placeholderTextView.textContainerInset, textView.textContainerInset)
        XCTAssertEqual(
            placeholderTextView.textContainer?.lineFragmentPadding,
            textView.textContainer?.lineFragmentPadding
        )
        let placeholderColor = try XCTUnwrap(
            placeholderTextView.textColor?.usingColorSpace(.deviceRGB)
        )
        let inputColor = try XCTUnwrap(textView.textColor?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(placeholderColor.redComponent, inputColor.redComponent, accuracy: 0.01)
        XCTAssertEqual(placeholderColor.greenComponent, inputColor.greenComponent, accuracy: 0.01)
        XCTAssertEqual(placeholderColor.blueComponent, inputColor.blueComponent, accuracy: 0.01)
        XCTAssertLessThan(placeholderColor.alphaComponent, inputColor.alphaComponent)
        XCTAssertEqual(ScreenshotPlainTextEditorMetrics.horizontalInset, 8)
        XCTAssertEqual(
            textView.frame.minX,
            ScreenshotPlainTextEditorMetrics.horizontalInset,
            accuracy: 0.1
        )
        let singleLinePlaceholderSize = ScreenshotPlainTextEditorMetrics.placeholderLayoutSize(
            inputFontSize: editorFont.pointSize,
            maximumWidth: .greatestFiniteMagnitude
        )
        XCTAssertGreaterThanOrEqual(
            textView.bounds.width,
            singleLinePlaceholderSize.width
                + ScreenshotPlainTextEditorMetrics.placeholderWidthSafety
        )
        for fontSize in ScreenshotAnnotationFontSize.allCases {
            let placeholderFontSize = ScreenshotPlainTextEditorMetrics.placeholderFontSize(
                for: fontSize.points
            )
            XCTAssertEqual(
                placeholderFontSize,
                fontSize.points,
                accuracy: 0.1
            )
            let placeholderWidth = NSAttributedString(
                string: ScreenshotPlainTextEditorMetrics.placeholderText,
                attributes: [.font: NSFont.systemFont(ofSize: placeholderFontSize)]
            ).size().width
            let contentSize = ScreenshotPlainTextEditorMetrics.placeholderContentSize(
                inputFontSize: fontSize.points,
                maximumWidth: imageFrame.width - 16,
                minimumSize: CGSize(width: 48, height: 32),
                displayScale: 1
            )
            XCTAssertGreaterThanOrEqual(
                contentSize.width,
                placeholderWidth + ScreenshotPlainTextEditorMetrics.placeholderWidthSafety
            )
        }
        for displayScale in [CGFloat(1), 2] {
            let narrowContentSize = ScreenshotPlainTextEditorMetrics.placeholderContentSize(
                inputFontSize: ScreenshotAnnotationFontSize.large.points * displayScale,
                maximumWidth: 64 * displayScale,
                minimumSize: CGSize(width: 48 * displayScale, height: 32 * displayScale),
                displayScale: displayScale
            )
            let narrowContainer = ScreenshotPlainTextEditorContainer(
                frame: CGRect(
                    origin: .zero,
                    size: CGSize(
                        width: narrowContentSize.width / displayScale
                            + ScreenshotPlainTextEditorMetrics.horizontalInset * 2,
                        height: narrowContentSize.height / displayScale
                    )
                )
            )
            let narrowEditor = narrowContainer.editor
            let narrowPlaceholder = narrowContainer.placeholder
            for view in [narrowPlaceholder, narrowEditor] {
                view.isRichText = false
                view.drawsBackground = false
                view.textContainerInset = .zero
                view.textContainer?.lineFragmentPadding = 0
                view.textContainer?.widthTracksTextView = true
                view.textContainer?.heightTracksTextView = false
                view.textContainer?.lineBreakMode = .byWordWrapping
                view.isVerticallyResizable = false
                view.font = .systemFont(ofSize: ScreenshotAnnotationFontSize.large.points)
            }
            narrowPlaceholder.string = ScreenshotPlainTextEditorMetrics.placeholderText
            narrowContainer.addSubview(narrowPlaceholder)
            narrowContainer.addSubview(narrowEditor)
            narrowContainer.layout()
            XCTAssertTrue(narrowEditor.string.isEmpty)
            XCTAssertEqual(
                narrowPlaceholder.frame,
                narrowEditor.frame
            )
            XCTAssertLessThanOrEqual(
                narrowPlaceholder.frame.maxX,
                narrowContainer.bounds.maxX - ScreenshotPlainTextEditorMetrics.horizontalInset
            )
            XCTAssertGreaterThanOrEqual(
                narrowPlaceholder.frame.minY,
                0,
                "scale=\(displayScale) content=\(narrowContentSize) container=\(narrowContainer.bounds) editor=\(narrowEditor.bounds) font=\(String(describing: narrowEditor.font))"
            )
            XCTAssertLessThanOrEqual(
                narrowPlaceholder.frame.maxY,
                narrowContainer.bounds.maxY,
                "scale=\(displayScale) content=\(narrowContentSize) container=\(narrowContainer.bounds) editor=\(narrowEditor.bounds) font=\(String(describing: narrowEditor.font))"
            )
            XCTAssertGreaterThan(
                narrowPlaceholder.bounds.height,
                singleLinePlaceholderSize.height
            )
        }
        let singleLineHeight = ceil(
            editorFont.ascender - editorFont.descender + editorFont.leading
        )
        let textViewFrame = textView.convert(textView.bounds, to: nil)
        let expectedObjectMidY = rootSize.height - (imageFrame.midY + 16)
        XCTAssertEqual(textView.alignment, .left)
        XCTAssertLessThanOrEqual(textView.bounds.height, singleLineHeight)
        XCTAssertEqual(
            textViewFrame.midY,
            expectedObjectMidY,
            accuracy: 1,
            "空文本编辑器应在 32 pt 初始对象框内垂直居中"
        )
        let topPaddingPoint = interactionView.convert(
            CGPoint(
                x: ScreenshotPlainTextEditorMetrics.horizontalInset + 2,
                y: 0.5
            ),
            to: nil
        )
        XCTAssertFalse(
            textView.bounds.contains(textView.convert(topPaddingPoint, from: nil)),
            "测试点应位于居中文本行之外"
        )
        XCTAssertTrue(
            ScreenshotPlainTextEditorInteraction.containsWindowPoint(
                topPaddingPoint,
                in: interactionView
            ),
            "文本行上方的留白仍应属于编辑对象的交互范围"
        )
        let placeholderTextContainer = try XCTUnwrap(placeholderTextView.textContainer)
        let placeholderLayoutManager = try XCTUnwrap(placeholderTextView.layoutManager)
        placeholderLayoutManager.ensureLayout(for: placeholderTextContainer)
        let placeholderGlyphBounds = placeholderLayoutManager.boundingRect(
            forGlyphRange: placeholderLayoutManager.glyphRange(for: placeholderTextContainer),
            in: placeholderTextContainer
        )
        let placeholderGlyphBoundsInWindow = placeholderTextView.convert(
            placeholderGlyphBounds.offsetBy(
                dx: placeholderTextView.textContainerOrigin.x,
                dy: placeholderTextView.textContainerOrigin.y
            ),
            to: nil
        )
        XCTAssertTrue(window.firstResponder === textView)
        textView.insertText(
            ScreenshotPlainTextEditorMetrics.placeholderText,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        XCTAssertFalse(textView.isPlaceholderVisible)
        XCTAssertTrue(placeholderTextView.isHidden)
        let updatedTextView = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(updatedTextView.textContainerInset, .zero)
        let textContainer = try XCTUnwrap(updatedTextView.textContainer)
        XCTAssertEqual(textContainer.lineFragmentPadding, 0)
        let layoutManager = try XCTUnwrap(updatedTextView.layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let glyphBounds = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        let glyphBoundsInWindow = updatedTextView.convert(
            glyphBounds.offsetBy(
                dx: updatedTextView.textContainerOrigin.x,
                dy: updatedTextView.textContainerOrigin.y
            ),
            to: nil
        )
        XCTAssertEqual(placeholderGlyphBoundsInWindow.origin.x, glyphBoundsInWindow.origin.x, accuracy: 0.5)
        XCTAssertEqual(placeholderGlyphBoundsInWindow.origin.y, glyphBoundsInWindow.origin.y, accuracy: 0.5)
        XCTAssertEqual(placeholderGlyphBounds.origin.x, glyphBounds.origin.x, accuracy: 0.5)
        XCTAssertEqual(placeholderGlyphBounds.origin.y, glyphBounds.origin.y, accuracy: 0.5)
        XCTAssertEqual(placeholderGlyphBounds.width, glyphBounds.width, accuracy: 0.5)
        XCTAssertEqual(placeholderGlyphBounds.height, glyphBounds.height, accuracy: 0.5)
        XCTAssertLessThan(glyphBounds.height, 30)
        XCTAssertLessThanOrEqual(glyphBounds.maxX, textContainer.containerSize.width)
        XCTAssertLessThan(updatedTextView.bounds.width, 140)

        updatedTextView.selectAll(nil)
        updatedTextView.insertText(
            "不该，不该，",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        let prefixTextView = try XCTUnwrap(window.firstResponder as? NSTextView)
        prefixTextView.setMarkedText(
            "333",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()

        let grownTextView = try XCTUnwrap(window.firstResponder as? NSTextView)
        let grownTextContainer = try XCTUnwrap(grownTextView.textContainer)
        let grownLayoutManager = try XCTUnwrap(grownTextView.layoutManager)
        grownLayoutManager.ensureLayout(for: grownTextContainer)
        let grownGlyphBounds = grownLayoutManager.boundingRect(
            forGlyphRange: grownLayoutManager.glyphRange(for: grownTextContainer),
            in: grownTextContainer
        )
        XCTAssertEqual(grownTextView.string, "不该，不该，333")
        XCTAssertEqual(
            grownTextContainer.containerSize.width,
            grownTextView.bounds.width,
            accuracy: 0.5
        )
        let expectedGrownWidth = ScreenshotTextLayout.fittedMultilineSize(
            text: "不该，不该，333",
            fontSize: ScreenshotAnnotationFontSize.large.points,
            maximumWidth: imageFrame.width - 16,
            minimumSize: CGSize(width: 1, height: 1)
        ).width
        XCTAssertEqual(grownTextView.bounds.width, expectedGrownWidth, accuracy: 1)
        XCTAssertLessThan(
            grownGlyphBounds.height,
            30,
            "view=\(grownTextView.bounds) container=\(grownTextContainer.containerSize) glyph=\(grownGlyphBounds) font=\(String(describing: grownTextView.font))"
        )
        XCTAssertTrue(grownTextView.hasMarkedText())

        grownTextView.unmarkText()
        grownTextView.selectAll(nil)
        grownTextView.insertText(
            ScreenshotPlainTextEditorMetrics.placeholderText,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        runMainLoop()
        let finalEditingTextView = try XCTUnwrap(window.firstResponder as? NSTextView)
        let finalEditingTextContainer = try XCTUnwrap(finalEditingTextView.textContainer)
        let finalEditingLayoutManager = try XCTUnwrap(finalEditingTextView.layoutManager)
        finalEditingLayoutManager.ensureLayout(for: finalEditingTextContainer)
        let finalEditingGlyphBounds = finalEditingLayoutManager.boundingRect(
            forGlyphRange: finalEditingLayoutManager.glyphRange(for: finalEditingTextContainer),
            in: finalEditingTextContainer
        )
        let finalEditingGlyphBoundsInWindow = finalEditingTextView.convert(
            finalEditingGlyphBounds.offsetBy(
                dx: finalEditingTextView.textContainerOrigin.x,
                dy: finalEditingTextView.textContainerOrigin.y
            ),
            to: nil
        )
        sendClick(
            to: window,
            swiftUIPoint: CGPoint(x: imageFrame.maxX - 20, y: imageFrame.maxY - 20),
            rootHeight: rootSize.height,
            throughApplication: true
        )
        runMainLoop()

        let contentView = try XCTUnwrap(window.contentView)
        let committedText = try XCTUnwrap(
            findTextView(
                with: ScreenshotPlainTextEditorMetrics.placeholderText,
                editable: false,
                below: contentView
            ),
            "提交预览必须继续使用 NSTextView/TextKit，避免切换到 NSTextField 后重新排版"
        )
        let committedTextContainer = try XCTUnwrap(committedText.textContainer)
        let committedLayoutManager = try XCTUnwrap(committedText.layoutManager)
        committedLayoutManager.ensureLayout(for: committedTextContainer)
        let committedGlyphBounds = committedLayoutManager.boundingRect(
            forGlyphRange: committedLayoutManager.glyphRange(for: committedTextContainer),
            in: committedTextContainer
        )
        let committedGlyphBoundsInWindow = committedText.convert(
            committedGlyphBounds.offsetBy(
                dx: committedText.textContainerOrigin.x,
                dy: committedText.textContainerOrigin.y
            ),
            to: nil
        )
        XCTAssertEqual(
            committedGlyphBoundsInWindow.origin.x,
            finalEditingGlyphBoundsInWindow.origin.x,
            accuracy: 0.5
        )
        XCTAssertEqual(
            committedGlyphBoundsInWindow.origin.y,
            finalEditingGlyphBoundsInWindow.origin.y,
            accuracy: 0.5
        )
        XCTAssertEqual(committedGlyphBounds.origin.x, placeholderGlyphBounds.origin.x, accuracy: 0.5)
        XCTAssertEqual(committedGlyphBounds.origin.y, placeholderGlyphBounds.origin.y, accuracy: 0.5)
        XCTAssertEqual(committedGlyphBounds.width, placeholderGlyphBounds.width, accuracy: 0.5)
        XCTAssertEqual(committedGlyphBounds.height, placeholderGlyphBounds.height, accuracy: 0.5)
        XCTAssertLessThan(committedText.bounds.width, 140)
        XCTAssertLessThan(committedText.bounds.height, 40)
    }

    @MainActor
    func testPlainTextPlaceholderKeepsGlobalOriginAtWrappingBoundaryForEachDisplayScale() throws {
        let rootSize = CGSize(width: 800, height: 600)
        let imageFrame = CGRect(x: 200, y: 100, width: 108, height: 300)
        let toolbarFrame = CGRect(x: 162, y: 450, width: 476, height: 68)

        for displayScale in [CGFloat(1), 2] {
            let toolbarMeasurement = ScreenshotCompactToolbarMeasurementSink()
            let editor = ScreenshotEditorView(
                image: try makeSolidImage(
                    width: Int(imageFrame.width * displayScale),
                    height: Int(imageFrame.height * displayScale)
                ),
                imageFrame: imageFrame,
                toolbarFrame: toolbarFrame,
                settings: ScreenCaptureSettings(
                    annotationTool: .text,
                    annotationFontSize: .large
                ),
                onSettingsChange: { _ in true },
                onCopy: { _ in },
                onCancel: {},
                registerEscapeHandler: { _ in },
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
                swiftUIPoint: compactControlCenter(textToolFrame, toolbarFrame: toolbarFrame),
                rootHeight: rootSize.height
            )
            sendClick(
                to: window,
                swiftUIPoint: CGPoint(x: imageFrame.minX + 8, y: imageFrame.midY),
                rootHeight: rootSize.height
            )
            runMainLoop()

            let textView = try XCTUnwrap(
                window.firstResponder as? ScreenshotPlainTextEditorTextView
            )
            let interactionView = try XCTUnwrap(textView.superview)
            let placeholderTextView = try XCTUnwrap(
                interactionView.subviews
                    .compactMap { $0 as? NSTextView }
                    .first { $0 !== textView }
            )
            let placeholderBounds = try glyphBoundsInWindow(for: placeholderTextView)
            let placeholderFirstLineBounds = try firstLineGlyphBoundsInWindow(
                for: placeholderTextView
            )
            XCTAssertGreaterThan(
                placeholderBounds.height,
                30,
                "scale=\(displayScale) 应覆盖占位换行边界"
            )

            textView.insertText(
                ScreenshotPlainTextEditorMetrics.placeholderText,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            runMainLoop()
            let inputBounds = try firstLineGlyphBoundsInWindow(for: textView)

            XCTAssertEqual(
                inputBounds.origin.x,
                placeholderFirstLineBounds.origin.x,
                accuracy: 0.5,
                "scale=\(displayScale)"
            )
            XCTAssertEqual(
                inputBounds.origin.y,
                placeholderFirstLineBounds.origin.y,
                accuracy: 0.5,
                "scale=\(displayScale)"
            )
        }
    }

    @MainActor
    private func textField(using editor: NSTextView, below root: NSView) -> NSTextField? {
        if let field = root as? NSTextField,
           field.currentEditor() === editor {
            return field
        }
        for subview in root.subviews {
            if let match = textField(using: editor, below: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func textField(
        with value: String,
        editable: Bool,
        below root: NSView
    ) -> NSTextField? {
        if let field = root as? NSTextField,
           field.stringValue == value,
           field.isEditable == editable {
            return field
        }
        for subview in root.subviews {
            if let match = textField(with: value, editable: editable, below: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func findTextView(
        with value: String,
        editable: Bool,
        below root: NSView
    ) -> NSTextView? {
        if let view = root as? NSTextView,
           view.string == value,
           view.isEditable == editable {
            return view
        }
        for subview in root.subviews {
            if let match = findTextView(with: value, editable: editable, below: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func glyphBoundsInWindow(for textView: NSTextView) throws -> CGRect {
        let textContainer = try XCTUnwrap(textView.textContainer)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let bounds = layoutManager.boundingRect(
            forGlyphRange: layoutManager.glyphRange(for: textContainer),
            in: textContainer
        )
        return textView.convert(
            bounds.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            ),
            to: nil
        )
    }

    @MainActor
    private func firstLineGlyphBoundsInWindow(for textView: NSTextView) throws -> CGRect {
        let textContainer = try XCTUnwrap(textView.textContainer)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let allGlyphs = layoutManager.glyphRange(for: textContainer)
        XCTAssertGreaterThan(allGlyphs.length, 0)
        var firstLineRange = NSRange()
        _ = layoutManager.lineFragmentUsedRect(
            forGlyphAt: allGlyphs.location,
            effectiveRange: &firstLineRange
        )
        let bounds = layoutManager.boundingRect(
            forGlyphRange: firstLineRange,
            in: textContainer
        )
        return textView.convert(
            bounds.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            ),
            to: nil
        )
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
        rootHeight: CGFloat,
        throughApplication: Bool = false
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
            if throughApplication {
                NSApp.sendEvent(mouseDown)
            } else {
                window.sendEvent(mouseDown)
            }
        }
        if let mouseUp {
            if throughApplication {
                NSApp.sendEvent(mouseUp)
            } else {
                window.sendEvent(mouseUp)
            }
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

    private func makeSplitImage(width: Int, height: Int) throws -> CGImage {
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
        context.setFillColor(CGColor(gray: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 0.92, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

@MainActor
private enum ScreenshotEditorTestWindowRetainer {
    static var windows: [NSWindow] = []
}
