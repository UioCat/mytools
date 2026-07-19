import AppKit
import MacToolsCore
import SwiftUI

@MainActor
final class MainPanelRouter: ObservableObject {
    @Published var selectedModule: MainToolModule = MainToolModule.defaultModule

    func open(_ module: MainToolModule) {
        selectedModule = module
    }
}

final class PanelDismissHandler {
    var onDismiss: () -> Void = {}

    func dismiss() {
        onDismiss()
    }
}

struct RuntimeMainWorkspaceView: View {
    @ObservedObject var router: MainPanelRouter
    @ObservedObject var model: ClipboardPanelModel
    let speechController: TranslationSpeechController
    let permissionService: PermissionService
    let defaultClipboardCacheDirectory: URL
    let onSaveClipboardSettings: (ClipboardSettings) throws -> AppSettings
    let onSaveTranslationSettings: (TranslationSettings) throws -> AppSettings
    let onSaveSuperRightClickSettings: (SuperRightClickSettings) throws -> AppSettings
    let onSaveWindowLayoutSettings: (WindowLayoutSettings) throws -> AppSettings
    let onSaveAppearanceMode: (AppAppearanceMode) throws -> AppSettings
    let onCopy: (ClipboardItem) -> Void
    let onCopyAndPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    @State private var currentSettings: AppSettings
    @State private var clipboardSearchFocusToken = 0

    init(
        router: MainPanelRouter,
        model: ClipboardPanelModel,
        settings: AppSettings,
        speechController: TranslationSpeechController,
        permissionService: PermissionService,
        defaultClipboardCacheDirectory: URL,
        onSaveClipboardSettings: @escaping (ClipboardSettings) throws -> AppSettings,
        onSaveTranslationSettings: @escaping (TranslationSettings) throws -> AppSettings,
        onSaveSuperRightClickSettings: @escaping (SuperRightClickSettings) throws -> AppSettings,
        onSaveWindowLayoutSettings: @escaping (WindowLayoutSettings) throws -> AppSettings,
        onSaveAppearanceMode: @escaping (AppAppearanceMode) throws -> AppSettings,
        onCopy: @escaping (ClipboardItem) -> Void,
        onCopyAndPaste: @escaping (ClipboardItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.router = router
        self.model = model
        self.speechController = speechController
        self.permissionService = permissionService
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.onSaveClipboardSettings = onSaveClipboardSettings
        self.onSaveTranslationSettings = onSaveTranslationSettings
        self.onSaveSuperRightClickSettings = onSaveSuperRightClickSettings
        self.onSaveWindowLayoutSettings = onSaveWindowLayoutSettings
        self.onSaveAppearanceMode = onSaveAppearanceMode
        self.onCopy = onCopy
        self.onCopyAndPaste = onCopyAndPaste
        self.onDismiss = onDismiss
        self._currentSettings = State(initialValue: settings)
    }

    var body: some View {
        MainWorkspaceView(
            selectedModule: $router.selectedModule,
            brandIcon: Image(nsImage: MenuBarLogoImage.make())
        ) {
            RuntimeSettingsView(
                settings: currentSettings,
                permissionService: permissionService,
                defaultClipboardCacheDirectory: defaultClipboardCacheDirectory,
                onSaveClipboardSettings: { clipboardSettings in
                    currentSettings = try onSaveClipboardSettings(clipboardSettings)
                },
                onSaveTranslationSettings: { translationSettings in
                    currentSettings = try onSaveTranslationSettings(translationSettings)
                },
                onSaveSuperRightClickSettings: { superRightClickSettings in
                    currentSettings = try onSaveSuperRightClickSettings(superRightClickSettings)
                },
                onSaveWindowLayoutSettings: { windowLayoutSettings in
                    currentSettings = try onSaveWindowLayoutSettings(windowLayoutSettings)
                },
                onSaveAppearanceMode: { appearanceMode in
                    currentSettings = try onSaveAppearanceMode(appearanceMode)
                },
                presentation: .embedded
            )
        } clipboard: {
            RuntimeClipboardModuleView(
                model: model,
                searchFocusToken: clipboardSearchFocusToken,
                onCopy: onCopy,
                onCopyAndPaste: onCopyAndPaste,
                onDismiss: onDismiss
            )
        } translation: {
            RuntimeTranslationModuleView(
                settings: currentSettings,
                speechController: speechController
            )
        }
        .onAppear {
            if router.selectedModule == .clipboard {
                model.prepareForPresentation()
                advanceClipboardSearchFocus()
            }
        }
        .onChange(of: router.selectedModule) { module in
            if module == .clipboard {
                model.prepareForPresentation()
                advanceClipboardSearchFocus()
            }
        }
    }

    private func advanceClipboardSearchFocus() {
        clipboardSearchFocusToken = ClipboardSearchFocusPolicy.focusToken(
            afterOpening: .clipboard,
            currentToken: clipboardSearchFocusToken
        )
    }
}

struct RuntimeClipboardModuleView: View {
    @ObservedObject var model: ClipboardPanelModel
    let searchFocusToken: Int
    let onCopy: (ClipboardItem) -> Void
    let onCopyAndPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        MainPanelView(
            items: model.items,
            resetToken: model.presentationToken,
            searchFocusToken: searchFocusToken,
            onSelect: { item, action in
                switch action {
                case .copy:
                    onCopy(item)
                case .copyAndPaste:
                    onCopyAndPaste(item)
                }
            },
            onFavoriteToggle: { item in
                model.toggleFavorite(item)
            },
            onDelete: { item in
                model.delete(item)
            },
            onClear: {
                model.clearNonFavorites()
            },
            onDismiss: onDismiss,
            presentation: .embedded
        )
        .onAppear {
            model.refresh()
        }
    }
}

struct RuntimeSettingsView: View {
    let settings: AppSettings
    let permissionService: PermissionService
    let defaultClipboardCacheDirectory: URL
    let onSaveClipboardSettings: (ClipboardSettings) throws -> Void
    let onSaveTranslationSettings: (TranslationSettings) throws -> Void
    let onSaveSuperRightClickSettings: (SuperRightClickSettings) throws -> Void
    let onSaveWindowLayoutSettings: (WindowLayoutSettings) throws -> Void
    let onSaveAppearanceMode: (AppAppearanceMode) throws -> Void
    let presentation: ToolModulePresentation
    @State private var permissionSummary: PermissionSummary

    init(
        settings: AppSettings,
        permissionService: PermissionService,
        defaultClipboardCacheDirectory: URL,
        onSaveClipboardSettings: @escaping (ClipboardSettings) throws -> Void,
        onSaveTranslationSettings: @escaping (TranslationSettings) throws -> Void,
        onSaveSuperRightClickSettings: @escaping (SuperRightClickSettings) throws -> Void,
        onSaveWindowLayoutSettings: @escaping (WindowLayoutSettings) throws -> Void,
        onSaveAppearanceMode: @escaping (AppAppearanceMode) throws -> Void,
        presentation: ToolModulePresentation = .window
    ) {
        self.settings = settings
        self.permissionService = permissionService
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.onSaveClipboardSettings = onSaveClipboardSettings
        self.onSaveTranslationSettings = onSaveTranslationSettings
        self.onSaveSuperRightClickSettings = onSaveSuperRightClickSettings
        self.onSaveWindowLayoutSettings = onSaveWindowLayoutSettings
        self.onSaveAppearanceMode = onSaveAppearanceMode
        self.presentation = presentation
        self._permissionSummary = State(initialValue: permissionService.summary())
    }

    var body: some View {
        SettingsView(
            settings: settings,
            permissionSummary: permissionSummary,
            openSystemSettings: permissionService.openSystemSettings,
            openPermissionSettings: permissionService.openSystemSettings(for:),
            saveClipboardSettings: onSaveClipboardSettings,
            saveTranslationSettings: onSaveTranslationSettings,
            saveSuperRightClickSettings: onSaveSuperRightClickSettings,
            saveWindowLayoutSettings: onSaveWindowLayoutSettings,
            saveAppearanceMode: onSaveAppearanceMode,
            defaultClipboardCacheDirectory: defaultClipboardCacheDirectory,
            presentation: presentation
        )
        .onAppear {
            permissionSummary = permissionService.summary()
        }
    }
}

struct RuntimeTranslationModuleView: View {
    let settings: AppSettings
    @ObservedObject var speechController: TranslationSpeechController
    @State private var inputText = ""
    @State private var isInputComposingText = false
    @State private var workspaceState: TranslationWorkspaceState = .idle
    @State private var translatedOriginalText = ""

    private var content: TranslationWorkspaceContent {
        TranslationWorkspaceContent(settings: settings.translation, state: workspaceState)
    }

    private var originalSpeechRequest: TranslationSpeechRequest? {
        content.originalSpeechRequest(text: inputText)
    }

    private var translatedSpeechRequest: TranslationSpeechRequest? {
        content.translatedSpeechRequest(originalText: translatedOriginalText)
    }

    private var isSpeakingOriginal: Bool {
        guard let originalSpeechRequest else {
            return false
        }

        return speechController.state.isSpeaking(originalSpeechRequest)
    }

    private var isSpeakingTranslation: Bool {
        guard let translatedSpeechRequest else {
            return false
        }

        return speechController.state.isSpeaking(translatedSpeechRequest)
    }

    private let inputEditorLayout = TranslationInputEditorLayout.standard
    private let workspaceLayout = TranslationWorkspaceLayout.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MainWorkspaceModuleHeader(
                module: .translation,
                subtitle: content.headerSubtitle
            )

            Text(content.helperText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .liquidGlassModule(cornerRadius: 22)

            HStack(alignment: .top, spacing: 12) {
                translationInputSection
                translationOutputSection
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .liquidGlassGroup(spacing: 12)
        .padding(18)
        .onChange(of: inputText) { _, _ in
            speechController.stop(ifSource: .translationWorkspace)
        }
        .onDisappear {
            speechController.stop(ifSource: .translationWorkspace)
        }
    }

    private var translationInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(content.inputTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Spacer(minLength: 0)

                speechButton(for: originalSpeechRequest, textRole: "原文")
            }

            ZStack(alignment: .topLeading) {
                if TranslationInputPlaceholderPolicy.isPlaceholderVisible(
                    inputText: inputText,
                    isComposingText: isInputComposingText
                ) {
                    Text(content.inputPlaceholder)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textTertiary)
                        .padding(.leading, inputEditorLayout.placeholderLeadingPadding)
                        .padding(.top, inputEditorLayout.placeholderTopPadding)
                        .allowsHitTesting(false)
                }

                TranslationTextInputEditor(
                    text: $inputText,
                    isComposingText: $isInputComposingText,
                    layout: inputEditorLayout
                ) {
                    translateInputText()
                }
            }
            .frame(
                minHeight: workspaceLayout.inputEditorMinimumHeight,
                maxHeight: .infinity
            )
            .padding(10)
            .liquidGlassModule(cornerRadius: 16)

            if isSpeakingOriginal, let originalSpeechRequest {
                speechStatus(for: originalSpeechRequest)
            }

            HStack(spacing: 10) {
                Button {
                    translateInputText()
                } label: {
                    Label(content.translateButtonTitle, systemImage: "arrow.right.circle.fill")
                        .font(.system(size: MacToolsControlMetrics.textActionFontSize, weight: .semibold))
                        .frame(minWidth: 92)
                }
                .buttonStyle(GlassPrimaryButtonStyle(cornerRadius: 14))
                .opacity(content.canSubmit(inputText: inputText) ? 1 : 0.45)
                .disabled(!content.canSubmit(inputText: inputText))

                if workspaceState == .translating {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .liquidGlassModule(cornerRadius: 22)
    }

    private var translationOutputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(content.outputTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Spacer(minLength: 0)

                speechButton(for: translatedSpeechRequest, textRole: "译文")

                Button {
                    copyOutputText()
                } label: {
                    Label(content.outputCopyButtonTitle, systemImage: "doc.on.doc")
                        .font(.system(size: MacToolsControlMetrics.textActionFontSize, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(content.copyableOutputText == nil ? MacToolsGlassTheme.textDisabled : MacToolsGlassTheme.textSecondary)
                .padding(.horizontal, MacToolsControlMetrics.textActionHorizontalPadding)
                .frame(height: MacToolsControlMetrics.textActionHeight)
                .liquidGlassButtonStyle(cornerRadius: 14, showsIdleSurface: content.copyableOutputText != nil)
                .disabled(content.copyableOutputText == nil)
            }

            TranslationOutputTextView(
                text: content.outputText,
                isPlaceholder: content.isOutputPlaceholder
            )
            .frame(
                minHeight: workspaceLayout.outputEditorMinimumHeight,
                maxHeight: .infinity
            )
            .padding(14)
            .liquidGlassModule(cornerRadius: 16)

            if isSpeakingTranslation, let translatedSpeechRequest {
                speechStatus(for: translatedSpeechRequest)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .liquidGlassModule(cornerRadius: 22)
        .animation(.easeInOut(duration: 0.16), value: isSpeakingTranslation)
    }

    private func speechButton(
        for request: TranslationSpeechRequest?,
        textRole: String
    ) -> some View {
        let isSpeaking = request.map(speechController.state.isSpeaking) ?? false
        let title = isSpeaking ? "停止朗读\(textRole)" : "朗读\(textRole)"

        return Button {
            guard let request else {
                return
            }
            speechController.toggle(request)
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(
                    width: MacToolsControlMetrics.inlineIconSize.width,
                    height: MacToolsControlMetrics.inlineIconSize.height
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            request == nil
                ? MacToolsGlassTheme.textTertiary
                : (isSpeaking ? Color.white : MacToolsGlassTheme.textSecondary)
        )
        .liquidGlassButtonStyle(
            cornerRadius: 12,
            isSelected: isSpeaking,
            minimumSize: MacToolsControlMetrics.inlineIconSize,
            showsIdleSurface: request != nil
        )
        .disabled(request == nil)
        .accessibilityLabel(title)
        .help(title)
    }

    private func speechStatus(for request: TranslationSpeechRequest) -> some View {
        Label(
            "正在朗读\(TranslationSpeechLanguagePolicy.displayName(for: request.languageCode)) · 系统音色",
            systemImage: "waveform"
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MacToolsGlassTheme.activeBlue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func copyOutputText() {
        guard let outputText = content.copyableOutputText else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }

    private func translateInputText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.canSubmit(inputText: text) else {
            return
        }

        speechController.stop(ifSource: .translationWorkspace)
        workspaceState = .translating
        Task {
            let service = TranslationService(
                provider: BailianTranslationProvider(configuration: settings.translation.bailianConfiguration)
            )
            let result = await service.translateAutomatically(text)

            await MainActor.run {
                switch result {
                case .success(let response):
                    translatedOriginalText = text
                    workspaceState = .translated(response.translatedText)
                case .failure(let error):
                    workspaceState = .failed(Self.message(for: error))
                }
            }
        }
    }

    private static func message(for error: TranslationError) -> String {
        switch error {
        case .providerNotConfigured:
            return "请先在设置里填写 DASHSCOPE_API_KEY。"
        case .networkUnavailable:
            return "无法连接到百炼服务，请检查网络后重试。"
        case .providerFailure(let message):
            return message
        }
    }
}

private struct TranslationTextInputEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposingText: Bool
    let layout: TranslationInputEditorLayout
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isComposingText: $isComposingText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TranslationInputTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onMarkedTextStateChange = context.coordinator.setComposingText(_:)
        textView.font = .systemFont(ofSize: 14, weight: .medium)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(
            width: layout.textContainerWidthInset,
            height: layout.textContainerHeightInset
        )
        textView.textContainer?.lineFragmentPadding = layout.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TranslationInputTextView else {
            return
        }

        textView.onSubmit = onSubmit
        textView.onMarkedTextStateChange = context.coordinator.setComposingText(_:)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(
            width: layout.textContainerWidthInset,
            height: layout.textContainerHeightInset
        )
        textView.textContainer?.lineFragmentPadding = layout.lineFragmentPadding
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var isComposingText: Bool

        init(text: Binding<String>, isComposingText: Binding<Bool>) {
            self._text = text
            self._isComposingText = isComposingText
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            setComposingText(textView.hasMarkedText())
        }

        func setComposingText(_ hasMarkedText: Bool) {
            guard isComposingText != hasMarkedText else {
                return
            }

            isComposingText = hasMarkedText
        }
    }
}

private final class TranslationInputTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onMarkedTextStateChange: (Bool) -> Void = { _ in }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        notifyMarkedTextState()
    }

    override func unmarkText() {
        super.unmarkText()
        notifyMarkedTextState()
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        notifyMarkedTextState()
    }

    override func didChangeText() {
        super.didChangeText()
        notifyMarkedTextState()
    }

    override func keyDown(with event: NSEvent) {
        if let command = TranslationInputKeyCommandResolver.command(
            forKeyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isCommandPressed: event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.command),
            isShiftPressed: event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.shift)
        ) {
            switch command {
            case .submit:
                onSubmit()
            case .insertNewline:
                insertNewline(nil)
            case .selectAll:
                selectAll(nil)
            case .copy:
                copy(nil)
            case .paste:
                paste(nil)
            case .cut:
                cut(nil)
            }
            return
        }

        super.keyDown(with: event)
    }

    private func notifyMarkedTextState() {
        onMarkedTextStateChange(hasMarkedText())
    }
}

private struct TranslationOutputTextView: NSViewRepresentable {
    var text: String
    var isPlaceholder: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TranslationOutputNSTextView()
        textView.font = .systemFont(ofSize: 14, weight: .medium)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        configure(textView)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TranslationOutputNSTextView else {
            return
        }

        configure(textView)
    }

    private func configure(_ textView: TranslationOutputNSTextView) {
        textView.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor
        if textView.string != text {
            textView.string = text
        }
    }
}

private final class TranslationOutputNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard let command = TranslationInputKeyCommandResolver.command(
            forKeyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            isCommandPressed: event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.command),
            isShiftPressed: event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .contains(.shift)
        ) else {
            super.keyDown(with: event)
            return
        }

        switch command {
        case .selectAll:
            selectAll(nil)
        case .copy:
            copy(nil)
        case .submit, .insertNewline, .paste, .cut:
            super.keyDown(with: event)
        }
    }
}
