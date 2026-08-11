// 截图标注编辑器的 SwiftUI 平台界面。
// 负责工具交互和草稿状态，最终像素合成委托给 MacToolsCore 渲染器。

import AppKit
import CoreGraphics
import SwiftUI

/// 标识截图编辑工具栏当前展示的唯一参数弹层。
private enum ScreenshotEditorParameterPopover {
    case color
    case lineWidth
    case fontSize
    case style
}

enum ScreenshotTextDraftKind {
    case text
    case label
}

struct ScreenshotTextDraft {
    let id: UUID?
    let kind: ScreenshotTextDraftKind
    var text: String
    var frame: CGRect
    var anchor: CGPoint
    var direction: ScreenshotLabelDirection
    var color: ScreenshotAnnotationColor
    var fontSize: CGFloat
    var maximumWidth: CGFloat

    func updatingStyle(
        color: ScreenshotAnnotationColor? = nil,
        fontSize: CGFloat? = nil,
        imageBounds: CGRect,
        textContentBounds: CGRect,
        imageWidth: CGFloat,
        scale: CGFloat
    ) -> ScreenshotTextDraft? {
        var updated = self
        updated.color = color ?? updated.color
        updated.fontSize = fontSize ?? updated.fontSize
        guard fontSize != nil else {
            return updated
        }
        switch updated.kind {
        case .text:
            let measured = updated.text.isEmpty
                ? ScreenshotPlainTextEditorMetrics.placeholderContentSize(
                    inputFontSize: updated.fontSize,
                    maximumWidth: updated.maximumWidth,
                    minimumSize: CGSize(width: 48 * scale, height: 32 * scale),
                    displayScale: scale
                )
                : ScreenshotTextLayout.fittedMultilineSize(
                    text: updated.text,
                    fontSize: updated.fontSize,
                    maximumWidth: updated.maximumWidth,
                    minimumSize: CGSize(width: 1, height: 1)
                )
            guard let frame = ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                updated.frame,
                requiredSize: measured,
                imageBounds: textContentBounds
            ) else {
                return nil
            }
            updated.frame = frame
        case .label:
            updated.maximumWidth = ScreenshotLabelStyle.normalizedMaximumBubbleWidth(
                existingMaximumWidth: updated.maximumWidth,
                in: imageWidth,
                fontSize: updated.fontSize,
                edgeInset: 8 * scale
            )
            let candidate = ScreenshotAnnotation.label(
                text: updated.text.isEmpty ? "输入标签" : updated.text,
                anchor: updated.anchor,
                direction: updated.direction,
                color: updated.color,
                fontSize: updated.fontSize,
                maximumWidth: updated.maximumWidth
            )
            guard let constrained = ScreenshotAnnotationEditingPolicy.constrained(
                candidate,
                to: imageBounds,
                canFlipLabel: true
            ),
            case let .label(_, anchor, direction, _, _, maximumWidth) = constrained else {
                return nil
            }
            updated.anchor = anchor
            updated.direction = direction
            updated.maximumWidth = maximumWidth
        }
        return updated
    }
}

private struct ScreenshotCompactToolbarFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
final class ScreenshotCompactToolbarMeasurementSink {
    private(set) var frames: [String: CGRect] = [:]

    func record(_ frames: [String: CGRect]) {
        self.frames = frames
    }
}

private struct ScreenshotCompactToolbarMeasurementKey: EnvironmentKey {
    static let defaultValue: ScreenshotCompactToolbarMeasurementSink? = nil
}

extension EnvironmentValues {
    var screenshotCompactToolbarMeasurement: ScreenshotCompactToolbarMeasurementSink? {
        get { self[ScreenshotCompactToolbarMeasurementKey.self] }
        set { self[ScreenshotCompactToolbarMeasurementKey.self] = newValue }
    }
}

/// 使用零行内边距的原生单行输入框，确保标签编辑态与 CoreText 测量宽度一致。
private struct ScreenshotLabelTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let foregroundColor: ScreenshotLabelColorComponents
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.cell = ScreenshotLabelTextFieldCell(textCell: "")
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.placeholderString = "输入标签"
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        configure(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text,
           !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) {
            field.stringValue = text
        }
        configure(field)
        context.coordinator.configureFieldEditor(for: field)
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.stopObservingFieldEditor()
    }

    private func configure(_ field: NSTextField) {
        field.font = .systemFont(ofSize: max(1, fontSize), weight: .medium)
        field.textColor = NSColor(
            calibratedRed: foregroundColor.red,
            green: foregroundColor.green,
            blue: foregroundColor.blue,
            alpha: foregroundColor.alpha
        )
        field.alignment = .center
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ScreenshotLabelTextField
        private weak var fieldEditor: NSTextView?
        private weak var observedTextStorage: NSTextStorage?
        private var textStorageSyncGeneration = 0

        init(parent: ScreenshotLabelTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            configureFieldEditor(for: field)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.text = field.stringValue.replacingOccurrences(of: "\n", with: " ")
            configureFieldEditor(for: field)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            stopObservingFieldEditor()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.onSubmit()
            return true
        }

        func configureFieldEditor(for field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView else {
                return
            }
            observeFieldEditor(editor)
            editor.textContainerInset = .zero
            editor.textContainer?.lineFragmentPadding = 0
            editor.alignment = .center
            editor.drawsBackground = false
        }

        @objc private func handleTextStorageDidProcessEditing(_ notification: Notification) {
            guard let textStorage = notification.object as? NSTextStorage,
                  textStorage === observedTextStorage,
                  let fieldEditor,
                  fieldEditor.textStorage === textStorage else {
                return
            }
            scheduleTextStorageSync(from: fieldEditor)
        }

        private func observeFieldEditor(_ editor: NSTextView) {
            guard fieldEditor !== editor || observedTextStorage !== editor.textStorage else {
                return
            }
            stopObservingFieldEditor()
            fieldEditor = editor
            observedTextStorage = editor.textStorage
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTextStorageDidProcessEditing(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: observedTextStorage
            )
        }

        func stopObservingFieldEditor() {
            textStorageSyncGeneration += 1
            if let observedTextStorage {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSTextStorage.didProcessEditingNotification,
                    object: observedTextStorage
                )
            }
            observedTextStorage = nil
            fieldEditor = nil
        }

        private func scheduleTextStorageSync(from editor: NSTextView) {
            textStorageSyncGeneration += 1
            let generation = textStorageSyncGeneration
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self,
                      let editor,
                      generation == self.textStorageSyncGeneration,
                      self.fieldEditor === editor else {
                    return
                }
                let value = editor.string.replacingOccurrences(of: "\n", with: " ")
                if self.parent.text != value {
                    self.parent.text = value
                }
            }
        }
    }
}

enum ScreenshotPlainTextEditorMetrics {
    static let placeholderText = "输入文本"
    static let horizontalInset: CGFloat = 8
    static let placeholderWidthSafety: CGFloat = 8
    static let placeholderDrawingOptions: NSString.DrawingOptions = [
        .usesLineFragmentOrigin,
        .usesFontLeading
    ]

    static func placeholderFontSize(for inputFontSize: CGFloat) -> CGFloat {
        max(1, inputFontSize)
    }

    static func placeholderAttributedText(
        inputFontSize: CGFloat,
        color: NSColor
    ) -> NSAttributedString {
        NSAttributedString(
            string: placeholderText,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: placeholderFontSize(for: inputFontSize)
                ),
                .foregroundColor: color
            ]
        )
    }

    static func placeholderLayoutSize(
        inputFontSize: CGFloat,
        maximumWidth: CGFloat
    ) -> CGSize {
        let bounds = placeholderAttributedText(
            inputFontSize: inputFontSize,
            color: .secondaryLabelColor
        ).boundingRect(
            with: CGSize(
                width: max(1, maximumWidth),
                height: .greatestFiniteMagnitude
            ),
            options: placeholderDrawingOptions
        )
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    static func placeholderContentSize(
        inputFontSize: CGFloat,
        maximumWidth: CGFloat,
        minimumSize: CGSize,
        displayScale: CGFloat
    ) -> CGSize {
        let resolvedDisplayScale = max(1, displayScale)
        let displayMaximumWidth = max(1, maximumWidth / resolvedDisplayScale)
        let displayMinimumSize = CGSize(
            width: minimumSize.width / resolvedDisplayScale,
            height: minimumSize.height / resolvedDisplayScale
        )
        let displayMeasured = placeholderLayoutSize(
            inputFontSize: inputFontSize / resolvedDisplayScale,
            maximumWidth: max(1, displayMaximumWidth - placeholderWidthSafety)
        )
        return CGSize(
            width: min(
                displayMaximumWidth,
                max(
                    displayMinimumSize.width,
                    displayMeasured.width + placeholderWidthSafety
                )
            ) * resolvedDisplayScale,
            height: max(displayMinimumSize.height, displayMeasured.height)
                * resolvedDisplayScale
        )
    }
}

/// 使用输入编辑器自身绘制占位，确保字号、基线和可访问性只有一个事实来源。
final class ScreenshotPlainTextEditorTextView: NSTextView {
    private(set) var placeholderAttributedText = NSAttributedString()
    private var placeholderInputFontSize = NSFont.systemFontSize

    var isPlaceholderVisible: Bool {
        string.isEmpty
    }

    var placeholderDrawingRect: CGRect {
        let size = ScreenshotPlainTextEditorMetrics.placeholderLayoutSize(
            inputFontSize: placeholderInputFontSize,
            maximumWidth: bounds.width
        )
        return CGRect(
            x: bounds.minX,
            y: bounds.midY - size.height / 2,
            width: bounds.width,
            height: size.height
        )
    }

    func configurePlaceholder(inputFontSize: CGFloat, color: NSColor) {
        placeholderInputFontSize = inputFontSize
        placeholderAttributedText = ScreenshotPlainTextEditorMetrics.placeholderAttributedText(
            inputFontSize: inputFontSize,
            color: color
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if string.isEmpty {
            placeholderAttributedText.draw(
                with: placeholderDrawingRect,
                options: ScreenshotPlainTextEditorMetrics.placeholderDrawingOptions
            )
        }
        super.draw(dirtyRect)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}

/// 在对象框内垂直居中原生文本视图，同时保持零文本内缩和左对齐。
final class ScreenshotPlainTextEditorContainer: NSView {
    let editor = ScreenshotPlainTextEditorTextView(frame: .zero)

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        guard let window else {
            return false
        }
        if window.firstResponder === editor {
            return true
        }
        return window.makeFirstResponder(editor)
    }

    override func layout() {
        super.layout()
        let fontSize = editor.font?.pointSize ?? NSFont.systemFontSize
        let horizontalInset = ScreenshotPlainTextEditorMetrics.horizontalInset
        let contentWidth = max(1, bounds.width - horizontalInset * 2)
        let contentHeight = editor.string.isEmpty
            ? ScreenshotPlainTextEditorMetrics.placeholderLayoutSize(
                inputFontSize: fontSize,
                maximumWidth: contentWidth
            ).height
            : ScreenshotTextLayout.fittedMultilineSize(
                text: editor.string,
                fontSize: fontSize,
                maximumWidth: contentWidth,
                minimumSize: CGSize(width: 1, height: 1)
            ).height
        let resolvedHeight = min(bounds.height, contentHeight)
        let contentFrame = CGRect(
            x: bounds.minX + horizontalInset,
            y: bounds.midY - resolvedHeight / 2,
            width: contentWidth,
            height: resolvedHeight
        )
        editor.frame = contentFrame
    }

    func refreshEditorLayout() {
        needsLayout = true
    }
}

enum ScreenshotPlainTextEditorInteraction {
    @MainActor
    static func containsWindowPoint(_ point: CGPoint, in interactionView: NSView) -> Bool {
        interactionView.bounds.contains(interactionView.convert(point, from: nil))
    }
}

/// 零内缩多行编辑器，使普通文本编辑态与 CoreText 的内容边界一致。
private struct ScreenshotPlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let color: ScreenshotAnnotationColor
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ScreenshotPlainTextEditorContainer {
        let container = ScreenshotPlainTextEditorContainer(frame: .zero)
        let editor = container.editor
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineBreakMode = .byWordWrapping
        editor.alignment = .left
        editor.isEditable = true
        editor.isSelectable = true
        editor.isVerticallyResizable = false
        editor.allowsUndo = true
        editor.setAccessibilityPlaceholderValue(ScreenshotPlainTextEditorMetrics.placeholderText)
        configure(editor)
        container.addSubview(editor)
        container.refreshEditorLayout()
        context.coordinator.installOutsideClickMonitor(
            for: editor,
            interactionView: container
        )
        context.coordinator.observeTextStorage(for: editor)
        return container
    }

    func updateNSView(_ container: ScreenshotPlainTextEditorContainer, context: Context) {
        let editor = container.editor
        context.coordinator.parent = self
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
        }
        configure(editor)
        container.refreshEditorLayout()
        context.coordinator.observeTextStorage(for: editor)
    }

    static func dismantleNSView(
        _ container: ScreenshotPlainTextEditorContainer,
        coordinator: Coordinator
    ) {
        let editor = container.editor
        coordinator.stopObservingTextStorage(for: editor)
        coordinator.removeOutsideClickMonitor()
    }

    private func configure(_ editor: ScreenshotPlainTextEditorTextView) {
        let font = NSFont.systemFont(ofSize: max(1, fontSize))
        editor.font = font
        editor.textColor = NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
        editor.alignment = .left
        editor.configurePlaceholder(inputFontSize: font.pointSize, color: .secondaryLabelColor)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScreenshotPlainTextEditor
        private weak var editor: NSTextView?
        private weak var observedTextStorage: NSTextStorage?
        private var outsideClickMonitor: Any?
        private var textStorageSyncGeneration = 0

        init(parent: ScreenshotPlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else {
                return
            }
            parent.text = editor.string
            (editor.superview as? ScreenshotPlainTextEditorContainer)?.refreshEditorLayout()
        }

        @objc private func handleTextStorageDidProcessEditing(_ notification: Notification) {
            guard let textStorage = notification.object as? NSTextStorage,
                  textStorage === observedTextStorage,
                  let editor,
                  editor.textStorage === textStorage else {
                return
            }
            textStorageSyncGeneration += 1
            let generation = textStorageSyncGeneration
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self,
                      let editor,
                      generation == self.textStorageSyncGeneration,
                      self.editor === editor else {
                    return
                }
                if self.parent.text != editor.string {
                    self.parent.text = editor.string
                }
                (editor.superview as? ScreenshotPlainTextEditorContainer)?.refreshEditorLayout()
            }
        }

        func observeTextStorage(for editor: NSTextView) {
            guard self.editor !== editor || observedTextStorage !== editor.textStorage else {
                return
            }
            if let observedTextStorage {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSTextStorage.didProcessEditingNotification,
                    object: observedTextStorage
                )
            }
            self.editor = editor
            observedTextStorage = editor.textStorage
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleTextStorageDidProcessEditing(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: observedTextStorage
            )
        }

        func stopObservingTextStorage(for editor: NSTextView) {
            textStorageSyncGeneration += 1
            if observedTextStorage === editor.textStorage,
               let observedTextStorage {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSTextStorage.didProcessEditingNotification,
                    object: observedTextStorage
                )
                self.observedTextStorage = nil
            }
        }

        func installOutsideClickMonitor(
            for editor: NSTextView,
            interactionView: NSView
        ) {
            removeOutsideClickMonitor()
            self.editor = editor
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
                [weak self, weak editor, weak interactionView] event in
                guard let self,
                      let editor,
                      let interactionView,
                      event.window === editor.window,
                      !ScreenshotPlainTextEditorInteraction.containsWindowPoint(
                          event.locationInWindow,
                          in: interactionView
                      ) else {
                    return event
                }
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onCommit()
                }
                return event
            }
        }

        func removeOutsideClickMonitor() {
            guard let outsideClickMonitor else {
                return
            }
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
            editor = nil
        }
    }
}

/// 标签已提交预览使用与编辑器相同的 AppKit 排版，避免 SwiftUI 二次测量后提前省略。
private struct ScreenshotLabelText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let foregroundColor: ScreenshotLabelColorComponents

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.cell = ScreenshotLabelTextFieldCell(textCell: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        configure(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
        configure(field)
    }

    private func configure(_ field: NSTextField) {
        field.font = .systemFont(ofSize: max(1, fontSize), weight: .medium)
        field.textColor = NSColor(
            calibratedRed: foregroundColor.red,
            green: foregroundColor.green,
            blue: foregroundColor.blue,
            alpha: foregroundColor.alpha
        )
        field.alignment = .center
    }
}

/// 普通文本预览按已测量边界绘制，避免 SwiftUI 再次扩张为固定宽度容器。
private struct ScreenshotPlainText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: ScreenshotAnnotationColor

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.cell = ScreenshotPlainTextFieldCell(textCell: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .none
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.usesSingleLineMode = false
        field.cell?.wraps = true
        configure(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.stringValue = text
        configure(field)
    }

    private func configure(_ field: NSTextField) {
        field.font = .systemFont(ofSize: max(1, fontSize))
        field.textColor = NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
        field.alignment = .left
    }
}

private final class ScreenshotPlainTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        rect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        rect
    }
}

/// 去除 NSTextFieldCell 默认水平内缩，并按真实字体行高垂直居中。
private final class ScreenshotLabelTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(in: rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(in: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: centeredTextRect(in: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        start selectionStart: Int,
        length selectionLength: Int
    ) {
        super.select(
            withFrame: centeredTextRect(in: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            start: selectionStart,
            length: selectionLength
        )
    }

    private func centeredTextRect(in bounds: NSRect) -> NSRect {
        let resolvedFont = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = min(
            bounds.height,
            ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        )
        return NSRect(
            x: bounds.minX,
            y: bounds.midY - lineHeight / 2,
            width: bounds.width,
            height: lineHeight
        )
    }
}

/// 扩展 `ScreenshotAnnotationTool`，补充本文件所需的屏幕捕获系统集成能力。
private extension ScreenshotAnnotationTool {
    var title: String {
        switch self {
        case .line:
            return "划线"
        case .freehand:
            return "画笔"
        case .arrow:
            return "箭头"
        case .rectangle:
            return "长方形"
        case .mosaic:
            return "马赛克"
        case .text:
            return "文本"
        case .label:
            return "标签"
        }
    }

    var imageName: String {
        switch self {
        case .line:
            return "line.diagonal"
        case .freehand:
            return "pencil.tip"
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .mosaic:
            return "checkerboard.rectangle"
        case .text:
            return "textformat"
        case .label:
            return "mappin.and.ellipse"
        }
    }
}

/// 封装 `ScreenshotEditorView` 在屏幕捕获系统集成中的值语义和相关操作。
public struct ScreenshotEditorView: View {
    let image: CGImage
    let imageFrame: CGRect
    let toolbarFrame: CGRect
    let onSettingsChange: (ScreenCaptureSettings) -> Bool
    let onCopy: (Data) -> Void
    let onCancel: () -> Void
    let registerEscapeHandler: (@escaping (Bool) -> ScreenshotEditorEscapeAction) -> Void
    let clearEscapeHandler: () -> Void

    @Environment(\.screenshotCompactToolbarMeasurement) private var compactToolbarMeasurement

    @State private var tool: ScreenshotAnnotationTool
    @State private var annotationColor: ScreenshotAnnotationColor
    @State private var annotationLineWidth: ScreenshotAnnotationLineWidth
    @State private var annotationFontSize: ScreenshotAnnotationFontSize
    @State private var annotationStore = ScreenshotAnnotationStore()
    @State private var dragStart: CGPoint?
    @State private var freehandStroke = ScreenshotFreehandStroke()
    @State private var previewAnnotation: ScreenshotAnnotation?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var mosaicPreviewImage: CGImage?
    @State private var pendingSettings: ScreenCaptureSettings?
    @State private var settingsSaveTask: Task<Void, Never>?
    @State private var presentedParameter: ScreenshotEditorParameterPopover?
    @State private var hoveredTool: ScreenshotAnnotationTool?
    @State private var isHoveringUndo = false
    @State private var selectedAnnotationID: UUID?
    @State private var editingDraft: ScreenshotTextDraft?
    @State private var draggedAnnotation: ScreenshotAnnotation?
    @State private var didDragSelectedAnnotation = false
    @FocusState private var isTextInputFocused: Bool

    /// 创建 `ScreenshotEditorView`，保存传入依赖并建立初始状态。
    public init(
        image: CGImage,
        imageFrame: CGRect,
        toolbarFrame: CGRect,
        settings: ScreenCaptureSettings,
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool,
        onCopy: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void,
        registerEscapeHandler: @escaping (@escaping (Bool) -> ScreenshotEditorEscapeAction) -> Void,
        clearEscapeHandler: @escaping () -> Void
    ) {
        self.image = image
        self.imageFrame = imageFrame
        self.toolbarFrame = toolbarFrame
        self.onSettingsChange = onSettingsChange
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.registerEscapeHandler = registerEscapeHandler
        self.clearEscapeHandler = clearEscapeHandler
        _tool = State(
            initialValue: ScreenshotAnnotationEditingPolicy.canUse(
                tool: settings.annotationTool,
                canvasSize: imageFrame.size,
                labelFontSize: settings.annotationFontSize.points
            ) ? settings.annotationTool : .line
        )
        _annotationColor = State(initialValue: settings.annotationColor.nearestPreset)
        _annotationLineWidth = State(initialValue: settings.annotationLineWidth)
        _annotationFontSize = State(initialValue: settings.annotationFontSize)
    }

    public var body: some View {
        GeometryReader { rootProxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .ignoresSafeArea()

                editorCanvas
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                editorToolbar
                    .frame(width: toolbarFrame.width, height: toolbarFrame.height)
                    .position(x: toolbarFrame.midX, y: toolbarFrame.midY)

                if selectedAnnotationID != nil, editingDraft == nil {
                    annotationInspector(rootSize: rootProxy.size)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(10)
                        .liquidGlassModule(cornerRadius: LiquidGlassCornerGeometry.smallControlRadius)
                        .position(x: toolbarFrame.midX, y: max(24, toolbarFrame.minY - 24))
                }
            }
        }
        .task(id: tool) {
            guard tool == .mosaic, mosaicPreviewImage == nil else {
                return
            }
            let sourceImage = image
            mosaicPreviewImage = try? await Task.detached(priority: .userInitiated) {
                try ScreenshotRenderer.mosaicImage(image: sourceImage)
            }.value
        }
        .onDisappear {
            flushPendingSettings()
            clearEscapeHandler()
        }
        .onAppear {
            registerEscapeHandler(handleEscape)
        }
        .onChange(of: isTextInputFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused, editingDraft != nil {
                commitEditing()
            }
        }
        .onDeleteCommand(perform: deleteSelectedAnnotation)
    }

    @ViewBuilder
    private var editorToolbar: some View {
        if toolbarFrame.width < ScreenCaptureEditorToolbarMetrics.ultraCompactBreakpoint {
            ScreenCaptureCompactToolbarLayout {
                compactToolbarControl("drawing-tools") { drawingToolMenu }
                compactToolbarControl("tool-text") {
                    toolButton(.text, showsSelectedTitle: false)
                }
                compactToolbarControl("tool-label") {
                    toolButton(.label, showsSelectedTitle: false)
                }
                compactToolbarControl("undo") { undoButton }
                compactToolbarControl("style") { compactStyleButton }
                compactToolbarControl("cancel") { cancelButton(compact: true) }
                compactToolbarControl("done") { doneButton(compact: true) }
            }
            .coordinateSpace(name: "screenshot-compact-toolbar")
            .onPreferenceChange(ScreenshotCompactToolbarFramePreferenceKey.self) {
                compactToolbarMeasurement?.record($0)
            }
            .liquidGlassPanel(cornerRadius: LiquidGlassCornerGeometry.screenshotToolbarRadius)
            .liquidGlassGroup(spacing: 2)
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
        } else if toolbarFrame.width < ScreenCaptureEditorToolbarMetrics.compactBreakpoint {
            ScreenCaptureCompactToolbarLayout {
                ForEach(ScreenshotAnnotationTool.allCases, id: \.self) { candidate in
                    compactToolbarControl("tool-\(candidate.rawValue)") {
                        toolButton(candidate, showsSelectedTitle: false)
                    }
                }
                compactToolbarControl("undo") { undoButton }
                compactToolbarControl("style") { compactStyleButton }
                compactToolbarControl("cancel") { cancelButton(compact: true) }
                compactToolbarControl("done") { doneButton(compact: true) }
            }
            .coordinateSpace(name: "screenshot-compact-toolbar")
            .onPreferenceChange(ScreenshotCompactToolbarFramePreferenceKey.self) {
                compactToolbarMeasurement?.record($0)
            }
            .liquidGlassPanel(cornerRadius: LiquidGlassCornerGeometry.screenshotToolbarRadius)
            .liquidGlassGroup(spacing: 2)
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
        } else {
            HStack(spacing: 6) {
            ForEach(ScreenshotAnnotationTool.allCases, id: \.self) { candidate in
                toolButton(candidate)
            }

                undoButton

                Divider()
                    .frame(height: 22)
                    .padding(.horizontal, 2)

                if tool != .mosaic {
                    colorParameterButton
                    if tool == .text || tool == .label {
                        fontSizeParameterButton
                    } else {
                        lineWidthParameterButton
                    }
                }

                Spacer(minLength: 6)

                cancelButton(compact: false)
                doneButton(compact: false)
            }
            .padding(10)
            .liquidGlassPanel(cornerRadius: LiquidGlassCornerGeometry.screenshotToolbarRadius)
            .liquidGlassGroup(spacing: 6)
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
        }
    }

    private func compactToolbarControl<Content: View>(
        _ id: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScreenshotCompactToolbarFramePreferenceKey.self,
                        value: [
                            id: proxy.frame(in: .named("screenshot-compact-toolbar"))
                        ]
                    )
                }
            }
    }

    private var undoButton: some View {
        Button(action: undoAnnotation) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .liquidGlassButtonHitTarget(
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacToolsGlassTheme.textSecondary)
        .liquidGlassInteractionSurface(
            state: isHoveringUndo ? .hovered : .idle,
            cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
        )
        .disabled(commandAction(.undo) != .undoAnnotation)
        .opacity(commandAction(.undo) == .undoAnnotation ? 1 : 0.35)
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityLabel("撤销")
        .accessibilityIdentifier("screenshot-undo")
        .help("撤销")
        .onHover { isHoveringUndo = $0 }
    }

    private var drawingToolMenu: some View {
        Menu {
            ForEach(drawingTools, id: \.self) { candidate in
                Button {
                    selectTool(candidate)
                } label: {
                    Label(candidate.title, systemImage: candidate.imageName)
                }
            }
        } label: {
            Image(systemName: drawingTools.contains(tool) ? tool.imageName : "scribble.variable")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 40)
                .liquidGlassButtonHitTarget(
                    cornerRadius: LiquidGlassCornerGeometry.controlRadius
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(drawingTools.contains(tool) ? MacToolsGlassTheme.activeBlue : MacToolsGlassTheme.textSecondary)
        .accessibilityLabel("绘制工具")
        .accessibilityIdentifier("screenshot-drawing-tools")
        .help("绘制工具")
    }

    private var drawingTools: [ScreenshotAnnotationTool] {
        [.line, .freehand, .arrow, .rectangle, .mosaic]
    }

    @ViewBuilder
    private func cancelButton(compact: Bool) -> some View {
        Button(action: onCancel) {
            if compact {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
            } else {
                Text("取消")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: MacToolsControlMetrics.textActionHeight)
            }
        }
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.controlRadius,
            minimumSize: compact
                ? MacToolsControlMetrics.toolbarIconSize
                : CGSize(width: 58, height: MacToolsControlMetrics.textActionHeight)
        )
        .disabled(isExporting)
        .accessibilityLabel("取消截图")
        .accessibilityIdentifier("screenshot-cancel")
    }

    @ViewBuilder
    private func doneButton(compact: Bool) -> some View {
        if compact {
            Button {
                copyScreenshot()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 40, height: 40)
                    .liquidGlassButtonHitTarget(
                        cornerRadius: LiquidGlassCornerGeometry.controlRadius
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassEffect(
                .regular.tint(MacToolsGlassTheme.activeBlue).interactive(),
                in: .rect(cornerRadius: LiquidGlassCornerGeometry.controlRadius)
            )
            .disabled(isExporting || commandAction(.complete) != .completeSession)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(isExporting ? "正在处理截图" : "完成截图")
            .accessibilityIdentifier("screenshot-done")
        } else {
            Button {
                copyScreenshot()
            } label: {
                Label(isExporting ? "处理中" : "完成", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(
                GlassPrimaryButtonStyle(
                    cornerRadius: LiquidGlassCornerGeometry.controlRadius
                )
            )
            .disabled(isExporting || commandAction(.complete) != .completeSession)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel(isExporting ? "正在处理截图" : "完成截图")
            .accessibilityIdentifier("screenshot-done")
        }
    }

    /// 构建一个默认透明、选中时蓝色浮起的标注工具按钮。
    private func toolButton(
        _ candidate: ScreenshotAnnotationTool,
        showsSelectedTitle: Bool = true
    ) -> some View {
        let isSelected = tool == candidate
        let isHovering = hoveredTool == candidate

        return Button {
            selectTool(candidate)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: candidate.imageName)
                    .font(.system(size: 14, weight: .semibold))

                if isSelected, showsSelectedTitle {
                    Text(candidate.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isSelected && showsSelectedTitle ? 10 : 0)
            .frame(minWidth: 40, minHeight: 40)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(MacToolsGlassTheme.activeBlue)
                        .frame(width: 20, height: 3)
                        .offset(y: -2)
                }
            }
            .liquidGlassButtonHitTarget(
                cornerRadius: LiquidGlassCornerGeometry.controlRadius
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? MacToolsGlassTheme.activeBlue : MacToolsGlassTheme.textSecondary)
        .liquidGlassInteractionSurface(
            state: isSelected ? .selected : (isHovering ? .hovered : .idle),
            cornerRadius: LiquidGlassCornerGeometry.controlRadius
        )
        .accessibilityLabel(candidate.title)
        .accessibilityIdentifier("screenshot-tool-\(candidate.rawValue)")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .disabled(!isToolAvailable(candidate))
        .opacity(isToolAvailable(candidate) ? 1 : 0.35)
        .help(isToolAvailable(candidate) ? candidate.title : "选区过小，无法使用\(candidate.title)")
        .onHover { hovering in
            hoveredTool = hovering ? candidate : nil
        }
    }

    private var colorParameterButton: some View {
        Button {
            presentedParameter = presentedParameter == .color ? nil : .color
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(swiftUIColor(annotationColor))
                    .frame(width: 15, height: 15)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.28), lineWidth: 1)
                    }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(width: 42, height: 40)
        }
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.controlRadius,
            minimumSize: CGSize(width: 42, height: 40)
        )
        .disabled(tool == .mosaic)
        .opacity(tool == .mosaic ? 0.35 : 1)
        .accessibilityLabel("标注颜色")
        .help("标注颜色")
        .popover(
            isPresented: parameterPopoverBinding(.color),
            arrowEdge: .top
        ) {
            colorParameterPopover
        }
    }

    private var lineWidthParameterButton: some View {
        Button {
            presentedParameter = presentedParameter == .lineWidth ? nil : .lineWidth
        } label: {
            HStack(spacing: 5) {
                ScreenshotLineWidthPreview()
                    .stroke(
                        MacToolsGlassTheme.textPrimary,
                        style: StrokeStyle(
                            lineWidth: annotationLineWidth.points,
                            lineCap: .round
                        )
                    )
                    .frame(width: 20, height: 12)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(width: 42, height: 40)
        }
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.controlRadius,
            minimumSize: CGSize(width: 42, height: 40)
        )
        .disabled(tool == .mosaic)
        .opacity(tool == .mosaic ? 0.35 : 1)
        .accessibilityLabel("标注粗细")
        .help("标注粗细")
        .popover(
            isPresented: parameterPopoverBinding(.lineWidth),
            arrowEdge: .top
        ) {
            lineWidthParameterPopover
        }
    }

    private var fontSizeParameterButton: some View {
        Button {
            presentedParameter = presentedParameter == .fontSize ? nil : .fontSize
        } label: {
            HStack(spacing: 5) {
                Text("A")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(width: 42, height: 40)
        }
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.controlRadius,
            minimumSize: CGSize(width: 42, height: 40)
        )
        .accessibilityLabel("文字大小")
        .help("文字大小")
        .popover(isPresented: parameterPopoverBinding(.fontSize), arrowEdge: .top) {
            fontSizeParameterPopover
        }
    }

    private var compactStyleButton: some View {
        Button {
            presentedParameter = presentedParameter == .style ? nil : .style
        } label: {
            ZStack(alignment: .bottomTrailing) {
                if tool == .mosaic {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Circle()
                        .fill(swiftUIColor(annotationColor))
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle().stroke(Color.primary.opacity(0.28), lineWidth: 1)
                        }
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 8, weight: .bold))
                        .offset(x: 5, y: 4)
                }
            }
            .frame(width: 40, height: 40)
        }
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.controlRadius,
            minimumSize: MacToolsControlMetrics.toolbarIconSize
        )
        .disabled(tool == .mosaic)
        .opacity(tool == .mosaic ? 0.35 : 1)
        .accessibilityLabel("标注样式")
        .accessibilityIdentifier("screenshot-style")
        .help("标注样式")
        .popover(isPresented: parameterPopoverBinding(.style), arrowEdge: .top) {
            compactStylePopover
        }
    }

    private var colorParameterPopover: some View {
        HStack(spacing: 8) {
            ForEach(ScreenshotAnnotationColor.presets, id: \.self) { color in
                colorButton(color)
            }
        }
        .padding(12)
        .liquidGlassGroup(spacing: 6)
    }

    private var lineWidthParameterPopover: some View {
        HStack(spacing: 8) {
            ForEach(ScreenshotAnnotationLineWidth.allCases, id: \.rawValue) { lineWidth in
                lineWidthButton(lineWidth)
            }
        }
        .padding(12)
        .liquidGlassGroup(spacing: 6)
    }

    private var fontSizeParameterPopover: some View {
        HStack(spacing: 8) {
            ForEach(ScreenshotAnnotationFontSize.allCases, id: \.rawValue) { fontSize in
                fontSizeButton(fontSize)
            }
        }
        .padding(12)
        .liquidGlassGroup(spacing: 6)
    }

    private var compactStylePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            colorParameterPopover
            Divider()
            if tool == .text || tool == .label {
                fontSizeParameterPopover
            } else {
                lineWidthParameterPopover
            }
        }
        .padding(4)
    }

    /// 由单一枚举状态派生参数弹层 Binding，避免颜色与粗细同时出现。
    private func parameterPopoverBinding(
        _ parameter: ScreenshotEditorParameterPopover
    ) -> Binding<Bool> {
        Binding(
            get: { presentedParameter == parameter },
            set: { isPresented in
                presentedParameter = isPresented ? parameter : nil
            }
        )
    }

    /// 构建并返回 `colorButton` 对应的 SwiftUI 界面内容或展示状态。
    private func colorButton(_ color: ScreenshotAnnotationColor) -> some View {
        Button {
            selectColor(color)
        } label: {
            Circle()
                .fill(swiftUIColor(color))
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(.primary.opacity(0.35), lineWidth: 1)
                }
                .padding(3)
                .liquidGlassInteractionSurface(
                    state: annotationColor == color ? .selected : .idle,
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
                .overlay {
                    if annotationColor == color {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .liquidGlassButtonHitTarget(
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
        }
        .buttonStyle(.plain)
        .help("选择\(colorName(color))")
        .accessibilityLabel(colorName(color))
        .accessibilityValue(annotationColor == color ? "已选择" : "未选择")
    }

    /// 构建并返回 `lineWidthButton` 对应的 SwiftUI 界面内容或展示状态。
    private func lineWidthButton(_ lineWidth: ScreenshotAnnotationLineWidth) -> some View {
        Button {
            annotationLineWidth = lineWidth
            persistSettings(
                tool: tool,
                color: annotationColor,
                lineWidth: lineWidth,
                fontSize: annotationFontSize
            )
        } label: {
            ScreenshotLineWidthPreview()
                .stroke(
                    Color.primary.opacity(0.88),
                    style: StrokeStyle(lineWidth: lineWidth.points, lineCap: .round)
                )
                .frame(width: 22, height: 12)
                .frame(width: 30, height: 22)
                .liquidGlassInteractionSurface(
                    state: annotationLineWidth == lineWidth ? .selected : .idle,
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
                .liquidGlassButtonHitTarget(
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
        }
        .buttonStyle(.plain)
        .help(lineWidthName(lineWidth))
        .accessibilityLabel(lineWidthName(lineWidth))
        .accessibilityValue(annotationLineWidth == lineWidth ? "已选择" : "未选择")
    }

    private func fontSizeButton(_ fontSize: ScreenshotAnnotationFontSize) -> some View {
        Button {
            selectFontSize(fontSize)
        } label: {
            Text(fontSizeName(fontSize))
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 38, height: 28)
                .liquidGlassInteractionSurface(
                    state: annotationFontSize == fontSize ? .selected : .idle,
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
                .liquidGlassButtonHitTarget(
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(fontSizeName(fontSize))字号")
        .accessibilityValue(annotationFontSize == fontSize ? "已选择" : "未选择")
    }

    /// 解析并返回 `selectColor` 对应的屏幕捕获系统集成结果。
    private func selectColor(_ color: ScreenshotAnnotationColor) {
        annotationColor = color
        updateSelectedAnnotation(color: color)
        persistSettings(
            tool: tool,
            color: color,
            lineWidth: annotationLineWidth,
            fontSize: annotationFontSize
        )
    }

    private func selectFontSize(_ fontSize: ScreenshotAnnotationFontSize) {
        annotationFontSize = fontSize
        updateSelectedAnnotation(fontSize: fontSize)
        persistSettings(
            tool: tool,
            color: annotationColor,
            lineWidth: annotationLineWidth,
            fontSize: fontSize
        )
    }

    /// 解析并返回 `selectTool` 对应的屏幕捕获系统集成结果。
    private func selectTool(_ tool: ScreenshotAnnotationTool) {
        if editingDraft != nil {
            commitEditing()
            guard editingDraft == nil else {
                return
            }
        }
        guard isToolAvailable(tool) else {
            errorMessage = tool == .text ? "选区过小，无法添加文本" : "选区过小，无法添加标签"
            return
        }
        self.tool = tool
        selectedAnnotationID = nil
        if tool == .mosaic {
            presentedParameter = nil
        }
        persistSettings(
            tool: tool,
            color: annotationColor,
            lineWidth: annotationLineWidth,
            fontSize: annotationFontSize
        )
    }

    private func isToolAvailable(_ tool: ScreenshotAnnotationTool) -> Bool {
        ScreenshotAnnotationEditingPolicy.canUse(
            tool: tool,
            canvasSize: imageFrame.size,
            labelFontSize: annotationFontSize.points
        )
    }

    /// 保存 `persistSettings` 接收的屏幕捕获系统集成数据，并保持既有持久化约束。
    private func persistSettings(
        tool: ScreenshotAnnotationTool,
        color: ScreenshotAnnotationColor,
        lineWidth: ScreenshotAnnotationLineWidth,
        fontSize: ScreenshotAnnotationFontSize
    ) {
        let settings = ScreenCaptureSettings(
            annotationTool: tool,
            annotationColor: color,
            annotationLineWidth: lineWidth,
            annotationFontSize: fontSize
        )
        pendingSettings = settings
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            commitPendingSettings()
        }
    }

    /// 构建并返回 `flushPendingSettings` 对应的 SwiftUI 界面内容或展示状态。
    private func flushPendingSettings() {
        settingsSaveTask?.cancel()
        commitPendingSettings()
    }

    /// 构建并返回 `commitPendingSettings` 对应的 SwiftUI 界面内容或展示状态。
    private func commitPendingSettings() {
        guard let pendingSettings else {
            return
        }
        settingsSaveTask = nil
        if onSettingsChange(pendingSettings) {
            self.pendingSettings = nil
            if errorMessage == "截图偏好保存失败，下次打开可能无法保留" {
                errorMessage = nil
            }
        } else {
            errorMessage = "截图偏好保存失败，下次打开可能无法保留"
        }
    }

    /// 构建并返回 `colorName` 对应的 SwiftUI 界面内容或展示状态。
    private func colorName(_ color: ScreenshotAnnotationColor) -> String {
        switch color {
        case .red:
            return "红色"
        case .orange:
            return "橙色"
        case .yellow:
            return "黄色"
        case .green:
            return "绿色"
        case .blue:
            return "蓝色"
        case .purple:
            return "紫色"
        case .black:
            return "黑色"
        case .white:
            return "白色"
        default:
            return "颜色"
        }
    }

    /// 构建并返回 `lineWidthName` 对应的 SwiftUI 界面内容或展示状态。
    private func lineWidthName(_ lineWidth: ScreenshotAnnotationLineWidth) -> String {
        switch lineWidth {
        case .thin:
            return "细线"
        case .medium:
            return "标准线"
        case .thick:
            return "粗线"
        }
    }

    private func fontSizeName(_ fontSize: ScreenshotAnnotationFontSize) -> String {
        switch fontSize {
        case .small:
            return "小"
        case .medium:
            return "中"
        case .large:
            return "大"
        }
    }

    private var editorCanvas: some View {
        GeometryReader { proxy in
            let imageRect = CGRect(origin: .zero, size: proxy.size)

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                Canvas { context, _ in
                    for annotation in annotationStore.annotations {
                        draw(annotation, in: &context, imageRect: imageRect)
                    }
                    if let previewAnnotation {
                        draw(previewAnnotation, in: &context, imageRect: imageRect, isPreview: true)
                    }
                    if tool == .freehand,
                       let freehandPreview = freehandAnnotation(imageRect: imageRect) {
                        draw(freehandPreview, in: &context, imageRect: imageRect, isPreview: true)
                    }
                }

                ForEach(annotationStore.items) { item in
                    if editingDraft?.id != item.id {
                        annotationPresentation(
                            item.id == selectedAnnotationID ? previewAnnotation ?? item.annotation : item.annotation,
                            imageRect: imageRect
                        )
                        .allowsHitTesting(false)
                    }
                }

                if let selectedAnnotationID,
                   editingDraft == nil,
                   let annotation = previewAnnotation
                    ?? annotationStore.item(id: selectedAnnotationID)?.annotation,
                   let bounds = annotation.editableBounds {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            MacToolsGlassTheme.selectionBlue,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                        .frame(
                            width: canvasRect(from: bounds, imageRect: imageRect).width + 6,
                            height: canvasRect(from: bounds, imageRect: imageRect).height + 6
                        )
                        .position(
                            x: canvasRect(from: bounds, imageRect: imageRect).midX,
                            y: canvasRect(from: bounds, imageRect: imageRect).midY
                        )
                        .allowsHitTesting(false)
                }

                if let editingDraft {
                    editingInput(for: editingDraft, imageRect: imageRect)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                annotationGesture(imageRect: imageRect),
                including: editingDraft == nil ? .all : .none
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        handleDoubleTap(at: value.location, imageRect: imageRect)
                    },
                including: editingDraft == nil ? .all : .none
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let editingDraft,
                              !editingCanvasBounds(for: editingDraft, imageRect: imageRect)
                                .contains(value.location) else {
                            return
                        }
                        commitEditing()
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }

    /// 构建并返回 `annotationGesture` 对应的 SwiftUI 界面内容或展示状态。
    private func annotationGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let point = imagePoint(from: value.location, imageRect: imageRect) else {
                    return
                }
                if tool == .text || tool == .label {
                    handleEditableDragChanged(at: point, imageRect: imageRect)
                    return
                }
                if dragStart == nil {
                    dragStart = point
                }
                guard let dragStart else {
                    return
                }
                if tool == .freehand {
                    freehandStroke.append(point)
                    return
                }
                previewAnnotation = annotation(from: dragStart, to: point, imageRect: imageRect)
            }
            .onEnded { value in
                defer {
                    dragStart = nil
                    freehandStroke = ScreenshotFreehandStroke()
                    previewAnnotation = nil
                    draggedAnnotation = nil
                    didDragSelectedAnnotation = false
                }
                guard let dragStart else {
                    return
                }

                if tool == .text || tool == .label {
                    finishEditableDrag(at: value.location, imageRect: imageRect)
                    return
                }

                if tool == .freehand {
                    if let point = imagePoint(from: value.location, imageRect: imageRect) {
                        freehandStroke.append(point)
                    }
                    guard let annotation = freehandAnnotation(imageRect: imageRect) else {
                        return
                    }
                    annotationStore.append(annotation)
                    return
                }

                guard let point = imagePoint(from: value.location, imageRect: imageRect),
                      distance(from: dragStart, to: point) >= 2 else {
                    return
                }
                annotationStore.append(annotation(from: dragStart, to: point, imageRect: imageRect))
            }
    }

    /// 构建并返回 `freehandAnnotation` 对应的 SwiftUI 界面内容或展示状态。
    private func freehandAnnotation(imageRect: CGRect) -> ScreenshotAnnotation? {
        freehandStroke.annotation(
            color: annotationColor,
            lineWidth: imageLineWidth(in: imageRect)
        )
    }

    /// 构建并返回 `annotation` 对应的 SwiftUI 界面内容或展示状态。
    private func annotation(
        from start: CGPoint,
        to end: CGPoint,
        imageRect: CGRect
    ) -> ScreenshotAnnotation {
        let lineWidth = imageLineWidth(in: imageRect)
        switch tool {
        case .line:
            return .line(start: start, end: end, color: annotationColor, lineWidth: lineWidth)
        case .freehand:
            return .freehand(points: [start, end], color: annotationColor, lineWidth: lineWidth)
        case .arrow:
            return .arrow(start: start, end: end, color: annotationColor, lineWidth: lineWidth)
        case .rectangle:
            return .rectangle(
                CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y),
                color: annotationColor,
                lineWidth: lineWidth
            )
        case .mosaic:
            return .mosaic(CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y))
        case .text, .label:
            return .mosaic(.zero)
        }
    }

    /// 构建并返回 `draw` 对应的 SwiftUI 界面内容或展示状态。
    private func draw(
        _ annotation: ScreenshotAnnotation,
        in context: inout GraphicsContext,
        imageRect: CGRect,
        isPreview: Bool = false
    ) {
        switch annotation {
        case let .line(start, end, color, lineWidth):
            let lineWidth = canvasLineWidth(lineWidth, in: imageRect)
            var path = Path()
            path.move(to: canvasPoint(from: start, imageRect: imageRect))
            path.addLine(to: canvasPoint(from: end, imageRect: imageRect))
            context.stroke(
                path,
                with: .color(displayColor(color, isPreview: isPreview)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        case let .freehand(points, color, lineWidth):
            guard let firstPoint = points.first else {
                return
            }
            let lineWidth = canvasLineWidth(lineWidth, in: imageRect)
            var path = Path()
            path.move(to: canvasPoint(from: firstPoint, imageRect: imageRect))
            for point in points.dropFirst() {
                path.addLine(to: canvasPoint(from: point, imageRect: imageRect))
            }
            context.stroke(
                path,
                with: .color(displayColor(color, isPreview: isPreview)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        case let .arrow(start, end, color, lineWidth):
            let lineWidth = canvasLineWidth(lineWidth, in: imageRect)
            let start = canvasPoint(from: start, imageRect: imageRect)
            let end = canvasPoint(from: end, imageRect: imageRect)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = ScreenshotAnnotationArrowStyle.headLength(forLineWidth: lineWidth)
            let headLeft = CGPoint(
                x: end.x - headLength * cos(angle - .pi / 6),
                y: end.y - headLength * sin(angle - .pi / 6)
            )
            let headRight = CGPoint(
                x: end.x - headLength * cos(angle + .pi / 6),
                y: end.y - headLength * sin(angle + .pi / 6)
            )
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            path.addLine(to: headLeft)
            path.move(to: end)
            path.addLine(to: headRight)
            context.stroke(
                path,
                with: .color(displayColor(color, isPreview: isPreview)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        case let .rectangle(rect, color, lineWidth):
            context.stroke(
                Path(canvasRect(from: rect, imageRect: imageRect)),
                with: .color(displayColor(color, isPreview: isPreview)),
                lineWidth: canvasLineWidth(lineWidth, in: imageRect)
            )
        case let .mosaic(rect):
            let rect = canvasRect(from: rect, imageRect: imageRect)
            if let mosaicPreviewImage {
                context.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    layer.draw(Image(decorative: mosaicPreviewImage, scale: 1), in: imageRect)
                }
            } else {
                context.fill(Path(rect), with: .color(.secondary.opacity(0.35)))
            }
            if ScreenshotMosaicOutlinePolicy.shouldShowOutline(isPreview: isPreview) {
                context.stroke(
                    Path(rect),
                    with: .color(.accentColor.opacity(0.72)),
                    lineWidth: 2
                )
            }
        case .text, .label:
            break
        }
    }

    @ViewBuilder
    private func annotationPresentation(
        _ annotation: ScreenshotAnnotation,
        imageRect: CGRect
    ) -> some View {
        switch annotation {
        case let .text(text, frame, color, fontSize):
            let rect = canvasRect(from: frame, imageRect: imageRect)
            ScreenshotPlainText(
                text: text,
                fontSize: canvasLineWidth(fontSize, in: imageRect),
                color: color
            )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        case let .label(text, anchor, direction, color, fontSize, maximumWidth):
            let geometry = ScreenshotTextLayout.labelGeometry(
                text: text,
                anchor: anchor,
                direction: direction,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
            let bubbleRect = canvasRect(from: geometry.bubbleRect, imageRect: imageRect)
            let dotRect = canvasRect(from: geometry.dotRect, imageRect: imageRect)
            let textRect = canvasRect(from: geometry.textRect, imageRect: imageRect)
            ZStack {
                labelBubble(
                    geometry: geometry,
                    fontSize: fontSize,
                    imageRect: imageRect,
                    isEditing: false
                )
                ScreenshotLabelText(
                    text: text,
                    fontSize: canvasLineWidth(fontSize, in: imageRect),
                    foregroundColor: ScreenshotLabelStyle.foregroundColor
                )
                    .frame(width: textRect.width, height: bubbleRect.height, alignment: .center)
                    .position(x: textRect.midX, y: bubbleRect.midY)
                Circle()
                    .fill(swiftUIColor(color))
                    .frame(width: dotRect.width, height: dotRect.height)
                    .position(x: dotRect.midX, y: dotRect.midY)
            }
        case .line, .freehand, .arrow, .rectangle, .mosaic:
            EmptyView()
        }
    }

    @ViewBuilder
    private func editingInput(
        for draft: ScreenshotTextDraft,
        imageRect: CGRect
    ) -> some View {
        switch draft.kind {
        case .text:
            let rect = canvasRect(from: draft.frame, imageRect: imageRect)
            ScreenshotPlainTextEditor(
                text: editingTextBinding,
                fontSize: canvasLineWidth(draft.fontSize, in: imageRect),
                color: draft.color,
                onCommit: commitEditing
            )
            .focused($isTextInputFocused)
            .frame(
                width: rect.width + ScreenshotPlainTextEditorMetrics.horizontalInset * 2,
                height: rect.height
            )
            .background(Color.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(MacToolsGlassTheme.selectionBlue, lineWidth: 1.5)
            }
            .position(x: rect.midX, y: rect.midY)
        case .label:
            let geometry = ScreenshotTextLayout.labelGeometry(
                text: draft.text.isEmpty ? "输入标签" : draft.text,
                anchor: draft.anchor,
                direction: draft.direction,
                fontSize: draft.fontSize,
                maximumWidth: draft.maximumWidth
            )
            let bubbleRect = canvasRect(from: geometry.bubbleRect, imageRect: imageRect)
            let dotRect = canvasRect(from: geometry.dotRect, imageRect: imageRect)
            let textRect = canvasRect(from: geometry.textRect, imageRect: imageRect)
            ZStack {
                labelBubble(
                    geometry: geometry,
                    fontSize: draft.fontSize,
                    imageRect: imageRect,
                    isEditing: true
                )
                ScreenshotLabelTextField(
                    text: editingTextBinding,
                    fontSize: canvasLineWidth(draft.fontSize, in: imageRect),
                    foregroundColor: ScreenshotLabelStyle.foregroundColor,
                    onSubmit: commitEditing
                )
                    .frame(width: textRect.width, height: bubbleRect.height, alignment: .center)
                    .focused($isTextInputFocused)
                    .position(x: textRect.midX, y: bubbleRect.midY)
                Circle()
                    .fill(swiftUIColor(draft.color))
                    .frame(width: dotRect.width, height: dotRect.height)
                    .position(x: dotRect.midX, y: dotRect.midY)
            }
        }
    }

    private func labelBubble(
        geometry: ScreenshotLabelGeometry,
        fontSize: CGFloat,
        imageRect: CGRect,
        isEditing: Bool
    ) -> some View {
        let bubbleRect = canvasRect(from: geometry.bubbleRect, imageRect: imageRect)
        let cornerRadius = canvasLineWidth(geometry.cornerRadius, in: imageRect)
        let outlineColor = isEditing
            ? MacToolsGlassTheme.selectionBlue
            : labelColor(ScreenshotLabelStyle.borderColor)
        let outlineWidth = isEditing
            ? 1.5
            : canvasLineWidth(ScreenshotLabelStyle.borderWidth(for: fontSize), in: imageRect)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(labelColor(ScreenshotLabelStyle.backgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(outlineColor, lineWidth: outlineWidth)
            }
            .shadow(
                color: labelColor(ScreenshotLabelStyle.shadowColor),
                radius: canvasLineWidth(
                    ScreenshotLabelStyle.shadowRadius(for: fontSize),
                    in: imageRect
                ),
                y: canvasLineWidth(
                    ScreenshotLabelStyle.shadowYOffset(for: fontSize),
                    in: imageRect
                )
            )
            .frame(width: bubbleRect.width, height: bubbleRect.height)
            .position(x: bubbleRect.midX, y: bubbleRect.midY)
    }

    private var editingTextBinding: Binding<String> {
        Binding(
            get: { editingDraft?.text ?? "" },
            set: { newValue in
                guard var draft = editingDraft else {
                    return
                }
                draft.text = draft.kind == .label
                    ? newValue.replacingOccurrences(of: "\n", with: " ")
                    : newValue
                let scale = imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
                switch draft.kind {
                case .text:
                    if let frame = fittedTextFrame(
                        for: draft,
                        text: draft.text
                    ) {
                        draft.frame = frame
                    }
                case .label:
                    draft.maximumWidth = ScreenshotLabelStyle.normalizedMaximumBubbleWidth(
                        existingMaximumWidth: draft.maximumWidth,
                        in: CGFloat(image.width),
                        fontSize: draft.fontSize,
                        edgeInset: 8 * scale
                    )
                }
                editingDraft = draft
            }
        )
    }

    private func fittedTextFrame(
        for draft: ScreenshotTextDraft,
        text: String
    ) -> CGRect? {
        let scale = imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
        let contentSize = text.isEmpty
            ? ScreenshotPlainTextEditorMetrics.placeholderContentSize(
                inputFontSize: draft.fontSize,
                maximumWidth: draft.maximumWidth,
                minimumSize: CGSize(width: 48 * scale, height: 32 * scale),
                displayScale: scale
            )
            : ScreenshotTextLayout.fittedMultilineSize(
                text: text,
                fontSize: draft.fontSize,
                maximumWidth: draft.maximumWidth,
                minimumSize: CGSize(width: 1, height: 1)
            )
        return ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
            draft.frame,
            requiredSize: contentSize,
            imageBounds: textContentBounds
        )
    }

    private func editingCanvasBounds(
        for draft: ScreenshotTextDraft,
        imageRect: CGRect
    ) -> CGRect {
        switch draft.kind {
        case .text:
            return canvasRect(from: draft.frame, imageRect: imageRect)
        case .label:
            let geometry = ScreenshotTextLayout.labelGeometry(
                text: draft.text.isEmpty ? "输入标签" : draft.text,
                anchor: draft.anchor,
                direction: draft.direction,
                fontSize: draft.fontSize,
                maximumWidth: draft.maximumWidth
            )
            return canvasRect(from: geometry.bounds, imageRect: imageRect)
        }
    }

    private func handleEditableDragChanged(at point: CGPoint, imageRect: CGRect) {
        if dragStart == nil {
            dragStart = point
            if let item = editableItem(at: point, imageRect: imageRect) {
                selectedAnnotationID = item.id
                draggedAnnotation = item.annotation
                syncStyleControls(with: item.annotation)
            } else {
                selectedAnnotationID = nil
                draggedAnnotation = nil
            }
            return
        }

        guard let dragStart, let draggedAnnotation else {
            return
        }
        let dx = point.x - dragStart.x
        let dy = point.y - dragStart.y
        didDragSelectedAnnotation = hypot(dx, dy) >= imageScale(for: imageRect) * 2
        previewAnnotation = ScreenshotAnnotationEditingPolicy.constrained(
            draggedAnnotation.offsetBy(dx: dx, dy: dy),
            to: constraintBounds(for: draggedAnnotation),
            canFlipLabel: true
        )
    }

    private func finishEditableDrag(at canvasPoint: CGPoint, imageRect: CGRect) {
        if let selectedAnnotationID,
           draggedAnnotation != nil,
           didDragSelectedAnnotation,
           let previewAnnotation {
            _ = annotationStore.update(id: selectedAnnotationID, annotation: previewAnnotation)
            return
        }

        if let draggedAnnotation,
           !didDragSelectedAnnotation,
           let dragStart,
           ScreenshotAnnotationEditingPolicy.hitTarget(
               at: dragStart,
               in: draggedAnnotation
           ) == .labelLocator {
            flipSelectedLabel()
            return
        }

        guard draggedAnnotation == nil,
              let dragStart,
              let endPoint = imagePoint(from: canvasPoint, imageRect: imageRect),
              distance(from: dragStart, to: endPoint) < imageScale(for: imageRect) * 3 else {
            return
        }
        beginNewTextAnnotation(at: dragStart, imageRect: imageRect)
    }

    private func handleDoubleTap(at canvasPoint: CGPoint, imageRect: CGRect) {
        guard editingDraft == nil,
              tool == .text || tool == .label,
              let point = imagePoint(from: canvasPoint, imageRect: imageRect),
              let item = editableItem(at: point, imageRect: imageRect) else {
            return
        }
        beginEditing(item)
    }

    private func editableItem(
        at point: CGPoint,
        imageRect: CGRect
    ) -> ScreenshotAnnotationItem? {
        let tolerance = imageScale(for: imageRect) * 5
        return annotationStore.items.reversed().first { item in
            ScreenshotAnnotationEditingPolicy.hitTarget(
                at: point,
                in: item.annotation,
                tolerance: tolerance
            ) != nil
        }
    }

    private func beginNewTextAnnotation(at point: CGPoint, imageRect: CGRect) {
        let scale = imageScale(for: imageRect)
        guard ScreenshotAnnotationEditingPolicy.canUse(
            tool: tool,
            canvasSize: imageRect.size,
            labelFontSize: annotationFontSize.points
        ) else {
            errorMessage = tool == .text ? "选区过小，无法添加文本" : "选区过小，无法添加标签"
            return
        }

        let fontSize = annotationFontSize.points * scale
        switch tool {
        case .text:
            let maximumWidth = textContentBounds.width
            let placeholderSize = ScreenshotPlainTextEditorMetrics.placeholderContentSize(
                inputFontSize: fontSize,
                maximumWidth: maximumWidth,
                minimumSize: CGSize(width: 48 * scale, height: 32 * scale),
                displayScale: scale
            )
            let initialFrame = CGRect(
                x: point.x,
                y: point.y - placeholderSize.height,
                width: placeholderSize.width,
                height: placeholderSize.height
            )
            guard let frame = ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                initialFrame,
                requiredSize: placeholderSize,
                imageBounds: textContentBounds
            ) else {
                errorMessage = "选区过小，无法添加文本"
                return
            }
            editingDraft = ScreenshotTextDraft(
                id: nil,
                kind: .text,
                text: "",
                frame: frame,
                anchor: .zero,
                direction: .left,
                color: annotationColor,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
        case .label:
            let maximumWidth = ScreenshotLabelStyle.maximumBubbleWidth(
                in: CGFloat(image.width),
                fontSize: fontSize,
                edgeInset: 8 * scale
            )
            let direction: ScreenshotLabelDirection = point.x <= CGFloat(image.width) / 2
                ? .left
                : .right
            let placeholder = ScreenshotAnnotation.label(
                text: "输入标签",
                anchor: point,
                direction: direction,
                color: annotationColor,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
            guard let constrained = ScreenshotAnnotationEditingPolicy.constrained(
                placeholder,
                to: imageBounds,
                canFlipLabel: true
            ),
            case let .label(_, anchor, fittedDirection, _, _, _) = constrained else {
                errorMessage = "选区过小，无法添加标签"
                return
            }
            editingDraft = ScreenshotTextDraft(
                id: nil,
                kind: .label,
                text: "",
                frame: .zero,
                anchor: anchor,
                direction: fittedDirection,
                color: annotationColor,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
        default:
            return
        }
        errorMessage = nil
        isTextInputFocused = true
    }

    private func beginEditing(_ item: ScreenshotAnnotationItem) {
        switch item.annotation {
        case let .text(text, frame, color, fontSize):
            let maximumWidth = textContentBounds.width
            let contentSize = ScreenshotTextLayout.fittedMultilineSize(
                text: text,
                fontSize: fontSize,
                maximumWidth: maximumWidth,
                minimumSize: CGSize(width: 1, height: 1)
            )
            editingDraft = ScreenshotTextDraft(
                id: item.id,
                kind: .text,
                text: text,
                frame: ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                    frame,
                    requiredSize: contentSize,
                    imageBounds: textContentBounds
                ) ?? frame,
                anchor: .zero,
                direction: .left,
                color: color,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
        case let .label(text, anchor, direction, color, fontSize, maximumWidth):
            let scale = imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
            editingDraft = ScreenshotTextDraft(
                id: item.id,
                kind: .label,
                text: text,
                frame: .zero,
                anchor: anchor,
                direction: direction,
                color: color,
                fontSize: fontSize,
                maximumWidth: ScreenshotLabelStyle.normalizedMaximumBubbleWidth(
                    existingMaximumWidth: maximumWidth,
                    in: CGFloat(image.width),
                    fontSize: fontSize,
                    edgeInset: 8 * scale
                )
            )
        default:
            return
        }
        selectedAnnotationID = item.id
        syncStyleControls(with: item.annotation)
        errorMessage = nil
        isTextInputFocused = true
    }

    private func commitEditing() {
        guard var draft = editingDraft else {
            return
        }
        guard ScreenshotAnnotationEditingPolicy.textCommitAction(for: draft.text) == .commit else {
            cancelEditing()
            return
        }

        let annotation: ScreenshotAnnotation
        switch draft.kind {
        case .text:
            let measured = ScreenshotTextLayout.fittedMultilineSize(
                text: draft.text,
                fontSize: draft.fontSize,
                maximumWidth: draft.maximumWidth,
                minimumSize: CGSize(width: 1, height: 1)
            )
            guard let frame = ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                draft.frame,
                requiredSize: measured,
                imageBounds: textContentBounds
            ) else {
                errorMessage = "文本内容超出截图高度，请缩短内容或减小字号"
                return
            }
            draft.frame = frame
            let candidate = ScreenshotAnnotation.text(
                text: draft.text,
                frame: draft.frame,
                color: draft.color,
                fontSize: draft.fontSize
            )
            guard let constrained = ScreenshotAnnotationEditingPolicy.constrained(
                candidate,
                to: textContentBounds,
                canFlipLabel: false
            ) else {
                errorMessage = "文本内容超出截图范围，请缩短内容或减小字号"
                return
            }
            annotation = constrained
        case .label:
            let scale = imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
            draft.maximumWidth = ScreenshotLabelStyle.normalizedMaximumBubbleWidth(
                existingMaximumWidth: draft.maximumWidth,
                in: CGFloat(image.width),
                fontSize: draft.fontSize,
                edgeInset: 8 * scale
            )
            let candidate = ScreenshotAnnotation.label(
                text: draft.text.replacingOccurrences(of: "\n", with: " "),
                anchor: draft.anchor,
                direction: draft.direction,
                color: draft.color,
                fontSize: draft.fontSize,
                maximumWidth: draft.maximumWidth
            )
            guard let constrained = ScreenshotAnnotationEditingPolicy.constrained(
                candidate,
                to: imageBounds,
                canFlipLabel: true
            ) else {
                errorMessage = "标签超出截图范围，请缩短内容或减小字号"
                return
            }
            annotation = constrained
        }

        if let id = draft.id {
            _ = annotationStore.update(id: id, annotation: annotation)
            selectedAnnotationID = id
        } else {
            selectedAnnotationID = annotationStore.append(annotation)
        }
        editingDraft = nil
        isTextInputFocused = false
        errorMessage = nil
    }

    private func cancelEditing() {
        editingDraft = nil
        isTextInputFocused = false
        errorMessage = nil
    }

    private func handleEscape(hasMarkedText: Bool) -> ScreenshotEditorEscapeAction {
        let action = ScreenshotEditorEscapePolicy.action(
            hasMarkedText: hasMarkedText,
            isEditing: editingDraft != nil,
            hasSelection: selectedAnnotationID != nil
        )
        switch action {
        case .cancelEditing:
            cancelEditing()
        case .deselect:
            selectedAnnotationID = nil
        case .forwardToInput, .cancelSession:
            break
        }
        return action
    }

    private func commandAction(
        _ command: ScreenshotEditorCommand
    ) -> ScreenshotEditorCommandAction {
        ScreenshotEditorCommandPolicy.action(
            for: command,
            isEditing: editingDraft != nil,
            hasSelection: selectedAnnotationID != nil,
            canUndo: annotationStore.canUndo
        )
    }

    private func undoAnnotation() {
        guard commandAction(.undo) == .undoAnnotation else {
            return
        }
        selectedAnnotationID = nil
        _ = annotationStore.undo()
    }

    private func deleteSelectedAnnotation() {
        guard commandAction(.delete) == .deleteSelection,
              let selectedAnnotationID else {
            return
        }
        _ = annotationStore.remove(id: selectedAnnotationID)
        self.selectedAnnotationID = nil
    }

    private func syncStyleControls(with annotation: ScreenshotAnnotation) {
        let color: ScreenshotAnnotationColor
        let fontSize: CGFloat
        switch annotation {
        case let .text(_, _, annotationColor, annotationFontSize):
            color = annotationColor
            fontSize = annotationFontSize
        case let .label(_, _, _, annotationColor, annotationFontSize, _):
            color = annotationColor
            fontSize = annotationFontSize
        default:
            return
        }
        annotationColor = color
        let displayPoints = fontSize / imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
        annotationFontSize = ScreenshotAnnotationFontSize.allCases.min {
            abs($0.points - displayPoints) < abs($1.points - displayPoints)
        } ?? .medium
    }

    private func syncStyleControls(with draft: ScreenshotTextDraft) {
        annotationColor = draft.color
        let displayPoints = draft.fontSize
            / imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
        annotationFontSize = ScreenshotAnnotationFontSize.allCases.min {
            abs($0.points - displayPoints) < abs($1.points - displayPoints)
        } ?? .medium
    }

    private func updateSelectedAnnotation(
        color: ScreenshotAnnotationColor? = nil,
        fontSize: ScreenshotAnnotationFontSize? = nil
    ) {
        let scale = imageScale(for: CGRect(origin: .zero, size: imageFrame.size))
        let requestedFontSize = fontSize.map { $0.points * scale }
        if let draft = editingDraft {
            guard let updatedDraft = draft.updatingStyle(
                color: color,
                fontSize: requestedFontSize,
                imageBounds: imageBounds,
                textContentBounds: textContentBounds,
                imageWidth: CGFloat(image.width),
                scale: scale
            ) else {
                errorMessage = draft.kind == .text
                    ? "文本内容超出截图高度，请减小字号"
                    : "标签超出截图范围，请减小字号"
                syncStyleControls(with: draft)
                return
            }
            editingDraft = updatedDraft
            errorMessage = nil
            return
        }
        guard let selectedAnnotationID,
              let item = annotationStore.item(id: selectedAnnotationID) else {
            return
        }
        let candidate: ScreenshotAnnotation
        switch item.annotation {
        case let .text(text, frame, existingColor, existingFontSize):
            let resolvedFontSize = requestedFontSize ?? existingFontSize
            var resolvedFrame = frame
            if requestedFontSize != nil {
                let measured = ScreenshotTextLayout.fittedMultilineSize(
                    text: text,
                    fontSize: resolvedFontSize,
                    maximumWidth: textContentBounds.width,
                    minimumSize: CGSize(width: 1, height: 1)
                )
                guard let resizedFrame = ScreenshotAnnotationEditingPolicy.resizedTextFramePreservingTop(
                    frame,
                    requiredSize: measured,
                    imageBounds: textContentBounds
                ) else {
                    errorMessage = "文本内容超出截图高度，请减小字号"
                    syncStyleControls(with: item.annotation)
                    return
                }
                resolvedFrame = resizedFrame
            }
            candidate = .text(
                text: text,
                frame: resolvedFrame,
                color: color ?? existingColor,
                fontSize: resolvedFontSize
            )
        case let .label(text, anchor, direction, existingColor, existingFontSize, maximumWidth):
            let resolvedFontSize = requestedFontSize ?? existingFontSize
            let resolvedMaximumWidth = ScreenshotLabelStyle.resolvedMaximumBubbleWidth(
                existingMaximumWidth: maximumWidth,
                in: CGFloat(image.width),
                requestedFontSize: requestedFontSize,
                edgeInset: 8 * scale
            )
            candidate = .label(
                text: text,
                anchor: anchor,
                direction: direction,
                color: color ?? existingColor,
                fontSize: resolvedFontSize,
                maximumWidth: ScreenshotLabelStyle.normalizedMaximumBubbleWidth(
                    existingMaximumWidth: resolvedMaximumWidth,
                    in: CGFloat(image.width),
                    fontSize: resolvedFontSize,
                    edgeInset: 8 * scale
                )
            )
        default:
            return
        }
        guard let annotation = ScreenshotAnnotationEditingPolicy.constrained(
            candidate,
            to: imageBounds,
            canFlipLabel: true
        ) else {
            errorMessage = "标注超出截图范围，请减小字号"
            syncStyleControls(with: item.annotation)
            return
        }
        _ = annotationStore.update(id: selectedAnnotationID, annotation: annotation)
        errorMessage = nil
    }

    private func flipSelectedLabel() {
        guard let selectedAnnotationID,
              let item = annotationStore.item(id: selectedAnnotationID),
              case let .label(text, anchor, direction, color, fontSize, maximumWidth) = item.annotation else {
            return
        }
        let candidate = ScreenshotAnnotation.label(
                text: text,
                anchor: anchor,
                direction: direction.flipped,
                color: color,
                fontSize: fontSize,
                maximumWidth: maximumWidth
            )
        guard let annotation = ScreenshotAnnotationEditingPolicy.constrained(
            candidate,
            to: imageBounds,
            canFlipLabel: false
        ) else {
            errorMessage = "当前空间不足，无法翻转标签"
            return
        }
        _ = annotationStore.update(id: selectedAnnotationID, annotation: annotation)
        errorMessage = nil
    }

    @ViewBuilder
    private func annotationInspector(rootSize: CGSize) -> some View {
        if let selectedAnnotationID,
           let item = annotationStore.item(id: selectedAnnotationID),
           item.annotation.editableBounds != nil {
            let isLabel: Bool = {
                if case .label = item.annotation {
                    return true
                }
                return false
            }()
            HStack(spacing: 4) {
                colorParameterButton
                ForEach(ScreenshotAnnotationFontSize.allCases, id: \.rawValue) { size in
                    fontSizeButton(size)
                }
                if isLabel {
                    Button(action: flipSelectedLabel) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .liquidGlassButtonHitTarget(
                                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                            )
                    }
                    .buttonStyle(.plain)
                    .help("翻转定位点")
                    .accessibilityLabel("翻转定位点")
                }
                Button(action: deleteSelectedAnnotation) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MacToolsGlassTheme.destructive)
                        .frame(width: 40, height: 40)
                        .liquidGlassButtonHitTarget(
                            cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                        )
                }
                .buttonStyle(.plain)
                .help("删除标注")
                .accessibilityLabel("删除标注")
            }
            .padding(6)
            .background(
                Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .liquidGlassFloatingSelection(cornerRadius: 14)
            .position(annotationInspectorPosition(for: item.annotation, rootSize: rootSize, isLabel: isLabel))
            .transition(.opacity)
            .animation(.easeOut(duration: 0.10), value: selectedAnnotationID)
        }
    }

    private func annotationInspectorPosition(
        for annotation: ScreenshotAnnotation,
        rootSize: CGSize,
        isLabel: Bool
    ) -> CGPoint {
        guard let bounds = annotation.editableBounds else {
            return CGPoint(x: imageFrame.midX, y: imageFrame.minY - 34)
        }
        let localRect = canvasRect(
            from: bounds,
            imageRect: CGRect(origin: .zero, size: imageFrame.size)
        )
        let objectRect = localRect.offsetBy(dx: imageFrame.minX, dy: imageFrame.minY)
        let inspectorWidth: CGFloat = isLabel ? 286 : 242
        let inspectorHeight: CGFloat = 52
        let preferredY = objectRect.minY - 8 - inspectorHeight / 2
        let y = preferredY >= 8
            ? preferredY
            : min(rootSize.height - inspectorHeight / 2 - 8, objectRect.maxY + 8 + inspectorHeight / 2)
        return CGPoint(
            x: min(
                max(inspectorWidth / 2 + 8, objectRect.midX),
                max(inspectorWidth / 2 + 8, rootSize.width - inspectorWidth / 2 - 8)
            ),
            y: y
        )
    }

    /// 构建并返回 `imageLineWidth` 对应的 SwiftUI 界面内容或展示状态。
    private func imageLineWidth(in imageRect: CGRect) -> CGFloat {
        guard imageRect.width > 0 else {
            return annotationLineWidth.points
        }
        return annotationLineWidth.points * CGFloat(image.width) / imageRect.width
    }

    private func imageScale(for imageRect: CGRect) -> CGFloat {
        guard imageRect.width > 0 else {
            return 1
        }
        return CGFloat(image.width) / imageRect.width
    }

    private var imageBounds: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
    }

    /// 普通文本在截图左右各留出 8pt 的显示安全区，避免选框描边被画布裁切。
    private var textContentBounds: CGRect {
        let displayBounds = CGRect(origin: .zero, size: imageFrame.size)
        return imageBounds.insetBy(dx: 8 * imageScale(for: displayBounds), dy: 0)
    }

    private func constraintBounds(for annotation: ScreenshotAnnotation) -> CGRect {
        if case .text = annotation {
            return textContentBounds
        }
        return imageBounds
    }

    /// 判断 `canvasLineWidth` 所描述的屏幕捕获系统集成条件是否成立。
    private func canvasLineWidth(_ imageLineWidth: CGFloat, in imageRect: CGRect) -> CGFloat {
        imageLineWidth * imageRect.width / CGFloat(image.width)
    }

    /// 构建并返回 `displayColor` 对应的 SwiftUI 界面内容或展示状态。
    private func displayColor(_ color: ScreenshotAnnotationColor, isPreview: Bool) -> Color {
        swiftUIColor(color).opacity(isPreview ? 0.72 : 1)
    }

    /// 构建并返回 `swiftUIColor` 对应的 SwiftUI 界面内容或展示状态。
    private func swiftUIColor(_ color: ScreenshotAnnotationColor) -> Color {
        Color(
            red: Double(color.red),
            green: Double(color.green),
            blue: Double(color.blue),
            opacity: Double(color.alpha)
        )
    }

    private func labelColor(_ color: ScreenshotLabelColorComponents) -> Color {
        Color(
            red: Double(color.red),
            green: Double(color.green),
            blue: Double(color.blue),
            opacity: Double(color.alpha)
        )
    }

    /// 构建并返回 `imagePoint` 对应的 SwiftUI 界面内容或展示状态。
    private func imagePoint(from canvasPoint: CGPoint, imageRect: CGRect) -> CGPoint? {
        guard imageRect.contains(canvasPoint) else {
            return nil
        }
        return CGPoint(
            x: (canvasPoint.x - imageRect.minX) * CGFloat(image.width) / imageRect.width,
            y: (imageRect.maxY - canvasPoint.y) * CGFloat(image.height) / imageRect.height
        )
    }

    /// 判断 `canvasPoint` 所描述的屏幕捕获系统集成条件是否成立。
    private func canvasPoint(from imagePoint: CGPoint, imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + imagePoint.x * imageRect.width / CGFloat(image.width),
            y: imageRect.maxY - imagePoint.y * imageRect.height / CGFloat(image.height)
        )
    }

    /// 判断 `canvasRect` 所描述的屏幕捕获系统集成条件是否成立。
    private func canvasRect(from imageRect: CGRect, imageRect canvasImageRect: CGRect) -> CGRect {
        let rect = imageRect.standardized
        let minPoint = canvasPoint(from: CGPoint(x: rect.minX, y: rect.minY), imageRect: canvasImageRect)
        let maxPoint = canvasPoint(from: CGPoint(x: rect.maxX, y: rect.maxY), imageRect: canvasImageRect)
        return CGRect(
            x: min(minPoint.x, maxPoint.x),
            y: min(minPoint.y, maxPoint.y),
            width: abs(maxPoint.x - minPoint.x),
            height: abs(maxPoint.y - minPoint.y)
        )
    }

    /// 计算并返回 `distance` 所描述的屏幕捕获系统集成结果。
    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    /// 执行 `copyScreenshot` 对应的屏幕捕获系统集成输入输出操作。
    private func copyScreenshot() {
        guard commandAction(.complete) == .completeSession else {
            return
        }
        let annotations = annotationStore.annotations
        let image = image
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotRenderer.pngData(image: image, annotations: annotations)
                }.value
                onCopy(data)
            } catch {
                errorMessage = "截图合成失败，请重试"
                isExporting = false
            }
        }
    }
}

/// 封装 `ScreenshotLineWidthPreview` 在屏幕捕获系统集成中的值语义和相关操作。
private struct ScreenshotLineWidthPreview: Shape {
    /// 构建并返回 `path` 对应的 SwiftUI 界面内容或展示状态。
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 3))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 4, y: rect.minY + 3),
            control1: CGPoint(x: rect.midX - 3, y: rect.maxY - 3),
            control2: CGPoint(x: rect.midX + 3, y: rect.minY + 3)
        )
        return path
    }
}
