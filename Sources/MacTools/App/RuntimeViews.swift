// `RuntimeViews` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import AppKit
import Combine
import MacToolsCore
import SwiftUI

/// 管理 `MainPanelRouter` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class MainPanelRouter: ObservableObject {
    @Published var selectedModule: MainToolModule = MainToolModule.defaultModule

    /// 展示 `open` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func open(_ module: MainToolModule) {
        selectedModule = module
    }
}

/// 管理 `SyncViewModel` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class SyncViewModel: ObservableObject {
    @Published var status: SyncStatus
    @Published var remoteSettings: AppSettings?
    @Published var folderPath: String?
    @Published var folderIsUbiquitous: Bool?
    @Published var devices: [SyncDeviceSummary]

    /// 创建 `SyncViewModel`，保存传入依赖并建立初始状态。
    init(status: SyncStatus = .unconfigured, folderPath: String? = nil) {
        self.status = status
        self.remoteSettings = nil
        self.folderPath = folderPath
        self.folderIsUbiquitous = nil
        self.devices = []
    }
}

/// 管理 `TranslationCredentialViewModel` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class TranslationCredentialViewModel: ObservableObject {
    @Published var apiKey: String
    @Published var isUnavailable: Bool

    /// 创建 `TranslationCredentialViewModel`，保存传入依赖并建立初始状态。
    init(apiKey: String = "", isUnavailable: Bool = false) {
        self.apiKey = apiKey
        self.isUnavailable = isUnavailable
    }
}

/// 管理 `PanelDismissHandler` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
final class PanelDismissHandler {
    var onDismiss: () -> Void = {}

    /// 取消或关闭 `dismiss` 对应的应用运行时与 AppKit 集成流程，并清理临时状态。
    func dismiss() {
        onDismiss()
    }
}

/// 封装 `RuntimeMainWorkspaceView` 在应用运行时与 AppKit 集成中的值语义和相关操作。
struct RuntimeMainWorkspaceView: View {
    @ObservedObject var router: MainPanelRouter
    @ObservedObject var model: ClipboardPanelModel
    @ObservedObject var syncModel: SyncViewModel
    @ObservedObject var translationCredentialModel: TranslationCredentialViewModel
    let speechController: TranslationSpeechController
    let permissionService: PermissionService
    let defaultClipboardCacheDirectory: URL
    let onSaveClipboardSettings: (ClipboardSettings) throws -> AppSettings
    let onSaveTranslationSettings: (TranslationSettings, Bool) async throws -> AppSettings
    let onSaveSuperRightClickSettings: (SuperRightClickSettings) throws -> AppSettings
    let onSaveWindowLayoutSettings: (WindowLayoutSettings) throws -> AppSettings
    let onSaveAppearanceMode: (AppAppearanceMode) throws -> AppSettings
    let onSaveSyncSettings: (SyncSettings) throws -> AppSettings
    let onSyncNow: () -> Void
    let onDeleteCloudData: () -> Void
    let onOpenClipboardStorageFolder: () -> Void
    let onSelectSyncFolder: () -> Void
    let onOpenSyncFolder: () -> Void
    let onRemoveSyncDevice: (String) -> Void
    let onCopy: (ClipboardItem) -> Void
    let onCopyAndPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    @State private var currentSettings: AppSettings
    @State private var translationCredentialUnavailable: Bool
    @State private var clipboardSearchFocusToken = 0

    /// 创建 `RuntimeMainWorkspaceView`，保存传入依赖并建立初始状态。
    init(
        router: MainPanelRouter,
        model: ClipboardPanelModel,
        settings: AppSettings,
        syncModel: SyncViewModel,
        translationCredentialModel: TranslationCredentialViewModel,
        speechController: TranslationSpeechController,
        permissionService: PermissionService,
        defaultClipboardCacheDirectory: URL,
        onSaveClipboardSettings: @escaping (ClipboardSettings) throws -> AppSettings,
        onSaveTranslationSettings: @escaping (TranslationSettings, Bool) async throws -> AppSettings,
        onSaveSuperRightClickSettings: @escaping (SuperRightClickSettings) throws -> AppSettings,
        onSaveWindowLayoutSettings: @escaping (WindowLayoutSettings) throws -> AppSettings,
        onSaveAppearanceMode: @escaping (AppAppearanceMode) throws -> AppSettings,
        onSaveSyncSettings: @escaping (SyncSettings) throws -> AppSettings,
        onSyncNow: @escaping () -> Void,
        onDeleteCloudData: @escaping () -> Void,
        onOpenClipboardStorageFolder: @escaping () -> Void,
        onSelectSyncFolder: @escaping () -> Void,
        onOpenSyncFolder: @escaping () -> Void,
        onRemoveSyncDevice: @escaping (String) -> Void,
        onCopy: @escaping (ClipboardItem) -> Void,
        onCopyAndPaste: @escaping (ClipboardItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.router = router
        self.model = model
        self.speechController = speechController
        self.permissionService = permissionService
        self.syncModel = syncModel
        self.translationCredentialModel = translationCredentialModel
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.onSaveClipboardSettings = onSaveClipboardSettings
        self.onSaveTranslationSettings = onSaveTranslationSettings
        self.onSaveSuperRightClickSettings = onSaveSuperRightClickSettings
        self.onSaveWindowLayoutSettings = onSaveWindowLayoutSettings
        self.onSaveAppearanceMode = onSaveAppearanceMode
        self.onSaveSyncSettings = onSaveSyncSettings
        self.onSyncNow = onSyncNow
        self.onDeleteCloudData = onDeleteCloudData
        self.onOpenClipboardStorageFolder = onOpenClipboardStorageFolder
        self.onSelectSyncFolder = onSelectSyncFolder
        self.onOpenSyncFolder = onOpenSyncFolder
        self.onRemoveSyncDevice = onRemoveSyncDevice
        self.onCopy = onCopy
        self.onCopyAndPaste = onCopyAndPaste
        self.onDismiss = onDismiss
        self._currentSettings = State(initialValue: settings)
        self._translationCredentialUnavailable = State(
            initialValue: translationCredentialModel.isUnavailable
        )
    }

    var body: some View {
        MainWorkspaceView(
            selectedModule: $router.selectedModule,
            brandIcon: Image(nsImage: MenuBarLogoImage.make())
        ) {
            RuntimeSettingsView(
                settings: currentSettings,
                syncModel: syncModel,
                translationCredentialUnavailable: translationCredentialUnavailable,
                permissionService: permissionService,
                defaultClipboardCacheDirectory: defaultClipboardCacheDirectory,
                onSaveClipboardSettings: { clipboardSettings in
                    currentSettings = try onSaveClipboardSettings(clipboardSettings)
                },
                onSaveTranslationSettings: { translationSettings, apiKeyWasEdited in
                    do {
                        currentSettings = try await onSaveTranslationSettings(
                            translationSettings,
                            apiKeyWasEdited
                        )
                        translationCredentialUnavailable = false
                    } catch {
                        translationCredentialUnavailable = true
                        throw error
                    }
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
                onSaveSyncSettings: { syncSettings in
                    currentSettings = try onSaveSyncSettings(syncSettings)
                },
                onSyncNow: onSyncNow,
                onDeleteCloudData: onDeleteCloudData,
                onOpenClipboardStorageFolder: onOpenClipboardStorageFolder,
                onSelectSyncFolder: onSelectSyncFolder,
                onOpenSyncFolder: onOpenSyncFolder,
                onRemoveSyncDevice: onRemoveSyncDevice,
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
        .onChange(of: router.selectedModule) { _, module in
            if module == .clipboard {
                model.prepareForPresentation()
                advanceClipboardSearchFocus()
            }
        }
        .onReceive(syncModel.$remoteSettings.compactMap { $0 }) { settings in
            currentSettings = settings
        }
        .onReceive(translationCredentialModel.$apiKey) { apiKey in
            guard currentSettings.translation.apiKey != apiKey else { return }
            currentSettings.translation.apiKey = apiKey
        }
        .onReceive(translationCredentialModel.$isUnavailable) { isUnavailable in
            translationCredentialUnavailable = isUnavailable
        }
    }

    /// 构建并返回 `advanceClipboardSearchFocus` 对应的 SwiftUI 界面内容或展示状态。
    private func advanceClipboardSearchFocus() {
        clipboardSearchFocusToken = ClipboardSearchFocusPolicy.focusToken(
            afterOpening: .clipboard,
            currentToken: clipboardSearchFocusToken
        )
    }
}

/// 封装 `RuntimeClipboardModuleView` 在应用运行时与 AppKit 集成中的值语义和相关操作。
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

/// 封装 `RuntimeSettingsView` 在应用运行时与 AppKit 集成中的值语义和相关操作。
struct RuntimeSettingsView: View {
    let settings: AppSettings
    @ObservedObject var syncModel: SyncViewModel
    let translationCredentialUnavailable: Bool
    let permissionService: PermissionService
    let defaultClipboardCacheDirectory: URL
    let onSaveClipboardSettings: (ClipboardSettings) throws -> Void
    let onSaveTranslationSettings: (TranslationSettings, Bool) async throws -> Void
    let onSaveSuperRightClickSettings: (SuperRightClickSettings) throws -> Void
    let onSaveWindowLayoutSettings: (WindowLayoutSettings) throws -> Void
    let onSaveAppearanceMode: (AppAppearanceMode) throws -> Void
    let onSaveSyncSettings: (SyncSettings) throws -> Void
    let onSyncNow: () -> Void
    let onDeleteCloudData: () -> Void
    let onOpenClipboardStorageFolder: () -> Void
    let onSelectSyncFolder: () -> Void
    let onOpenSyncFolder: () -> Void
    let onRemoveSyncDevice: (String) -> Void
    let presentation: ToolModulePresentation
    @State private var permissionSummary: PermissionSummary

    /// 创建 `RuntimeSettingsView`，保存传入依赖并建立初始状态。
    init(
        settings: AppSettings,
        syncModel: SyncViewModel,
        translationCredentialUnavailable: Bool,
        permissionService: PermissionService,
        defaultClipboardCacheDirectory: URL,
        onSaveClipboardSettings: @escaping (ClipboardSettings) throws -> Void,
        onSaveTranslationSettings: @escaping (TranslationSettings, Bool) async throws -> Void,
        onSaveSuperRightClickSettings: @escaping (SuperRightClickSettings) throws -> Void,
        onSaveWindowLayoutSettings: @escaping (WindowLayoutSettings) throws -> Void,
        onSaveAppearanceMode: @escaping (AppAppearanceMode) throws -> Void,
        onSaveSyncSettings: @escaping (SyncSettings) throws -> Void,
        onSyncNow: @escaping () -> Void,
        onDeleteCloudData: @escaping () -> Void,
        onOpenClipboardStorageFolder: @escaping () -> Void,
        onSelectSyncFolder: @escaping () -> Void,
        onOpenSyncFolder: @escaping () -> Void,
        onRemoveSyncDevice: @escaping (String) -> Void,
        presentation: ToolModulePresentation = .window
    ) {
        self.settings = settings
        self.permissionService = permissionService
        self.syncModel = syncModel
        self.translationCredentialUnavailable = translationCredentialUnavailable
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.onSaveClipboardSettings = onSaveClipboardSettings
        self.onSaveTranslationSettings = onSaveTranslationSettings
        self.onSaveSuperRightClickSettings = onSaveSuperRightClickSettings
        self.onSaveWindowLayoutSettings = onSaveWindowLayoutSettings
        self.onSaveAppearanceMode = onSaveAppearanceMode
        self.onSaveSyncSettings = onSaveSyncSettings
        self.onSyncNow = onSyncNow
        self.onDeleteCloudData = onDeleteCloudData
        self.onOpenClipboardStorageFolder = onOpenClipboardStorageFolder
        self.onSelectSyncFolder = onSelectSyncFolder
        self.onOpenSyncFolder = onOpenSyncFolder
        self.onRemoveSyncDevice = onRemoveSyncDevice
        self.presentation = presentation
        self._permissionSummary = State(initialValue: permissionService.summary())
    }

    var body: some View {
        SettingsView(
            settings: settings,
            syncStatus: syncModel.status,
            syncFolderPath: syncModel.folderPath,
            syncFolderIsUbiquitous: syncModel.folderIsUbiquitous,
            syncDevices: syncModel.devices,
            translationCredentialUnavailable: translationCredentialUnavailable,
            permissionSummary: permissionSummary,
            openSystemSettings: permissionService.openSystemSettings,
            openPermissionSettings: permissionService.requestPermissionAndOpenSystemSettings(for:),
            openClipboardStorageFolder: onOpenClipboardStorageFolder,
            saveClipboardSettings: onSaveClipboardSettings,
            saveTranslationSettings: onSaveTranslationSettings,
            saveSuperRightClickSettings: onSaveSuperRightClickSettings,
            saveWindowLayoutSettings: onSaveWindowLayoutSettings,
            saveAppearanceMode: onSaveAppearanceMode,
            saveSyncSettings: onSaveSyncSettings,
            syncNow: onSyncNow,
            deleteCloudData: onDeleteCloudData,
            selectSyncFolder: onSelectSyncFolder,
            openSyncFolder: onOpenSyncFolder,
            removeSyncDevice: onRemoveSyncDevice,
            defaultClipboardCacheDirectory: defaultClipboardCacheDirectory,
            presentation: presentation
        )
        .onAppear {
            permissionSummary = permissionService.summary()
        }
    }
}

/// 封装 `RuntimeTranslationModuleView` 在应用运行时与 AppKit 集成中的值语义和相关操作。
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

    /// 构建并返回 `speechButton` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `speechStatus` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 执行 `copyOutputText` 对应的应用运行时与 AppKit 集成输入输出操作。
    private func copyOutputText() {
        guard let outputText = content.copyableOutputText else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }

    /// 提交当前输入并将异步翻译结果写回工作区状态。
    private func translateInputText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard content.canSubmit(inputText: text) else {
            return
        }

        speechController.stop(ifSource: .translationWorkspace)
        workspaceState = .translating
        Task {
            // 当前实现未使用请求代际；若允许连续提交，较晚完成的旧请求仍可能覆盖新结果。
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

    /// 构建并返回 `message` 对应的 SwiftUI 界面内容或展示状态。
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

/// 封装 `TranslationTextInputEditor` 在应用运行时与 AppKit 集成中的值语义和相关操作。
private struct TranslationTextInputEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposingText: Bool
    let layout: TranslationInputEditorLayout
    let onSubmit: () -> Void

    /// 构造并返回 `makeCoordinator` 所描述的应用运行时与 AppKit 集成对象。
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isComposingText: $isComposingText)
    }

    /// 构造并返回 `makeNSView` 所描述的应用运行时与 AppKit 集成对象。
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

    /// 应用 `updateNSView` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
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

    /// 管理 `Coordinator` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var isComposingText: Bool

        /// 创建 `Coordinator`，保存传入依赖并建立初始状态。
        init(text: Binding<String>, isComposingText: Binding<Bool>) {
            self._text = text
            self._isComposingText = isComposingText
        }

        /// 构建并返回 `textDidChange` 对应的 SwiftUI 界面内容或展示状态。
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text = textView.string
            setComposingText(textView.hasMarkedText())
        }

        /// 应用 `setComposingText` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
        func setComposingText(_ hasMarkedText: Bool) {
            guard isComposingText != hasMarkedText else {
                return
            }

            isComposingText = hasMarkedText
        }
    }
}

/// 管理 `TranslationInputTextView` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
private final class TranslationInputTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onMarkedTextStateChange: (Bool) -> Void = { _ in }

    /// 应用 `setMarkedText` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        notifyMarkedTextState()
    }

    /// 构建并返回 `unmarkText` 对应的 SwiftUI 界面内容或展示状态。
    override func unmarkText() {
        super.unmarkText()
        notifyMarkedTextState()
    }

    /// 保存 `insertText` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        notifyMarkedTextState()
    }

    /// 响应 `didChangeText` 对应的系统或界面回调，并同步当前交互状态。
    override func didChangeText() {
        super.didChangeText()
        notifyMarkedTextState()
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
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

    /// 发布或记录 `notifyMarkedTextState` 对应的应用运行时与 AppKit 集成状态。
    private func notifyMarkedTextState() {
        onMarkedTextStateChange(hasMarkedText())
    }
}

/// 封装 `TranslationOutputTextView` 在应用运行时与 AppKit 集成中的值语义和相关操作。
private struct TranslationOutputTextView: NSViewRepresentable {
    var text: String
    var isPlaceholder: Bool

    /// 构造并返回 `makeNSView` 所描述的应用运行时与 AppKit 集成对象。
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

    /// 应用 `updateNSView` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? TranslationOutputNSTextView else {
            return
        }

        configure(textView)
    }

    /// 应用 `configure` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    private func configure(_ textView: TranslationOutputNSTextView) {
        textView.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor
        if textView.string != text {
            textView.string = text
        }
    }
}

/// 管理 `TranslationOutputNSTextView` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
private final class TranslationOutputNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool {
        true
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
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
