// `SettingsView` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import AppKit
import SwiftUI

/// 封装 `SettingsView` 在 SwiftUI 展示层中的值语义和相关操作。
public struct SettingsView: View {
    @Binding private var selectedPane: SettingsPane
    public let settings: AppSettings
    public let syncStatus: SyncStatus
    public let syncFolderPath: String?
    public let syncFolderIsUbiquitous: Bool?
    public let syncDevices: [SyncDeviceSummary]
    public let translationCredentialUnavailable: Bool
    public let permissionSummary: PermissionSummary
    public let openSystemSettings: () -> Void
    public let openPermissionSettings: (AppPermission) -> Void
    public let openClipboardStorageFolder: () -> Void
    public let saveClipboardSettings: (ClipboardSettings) throws -> Void
    public let saveTranslationSettings: (TranslationSettings, Bool) async throws -> Void
    public let saveSuperRightClickSettings: (SuperRightClickSettings) throws -> Void
    public let saveWindowLayoutSettings: (WindowLayoutSettings) throws -> Void
    public let saveAppearanceMode: (AppAppearanceMode) throws -> Void
    public let saveSyncSettings: (SyncSettings) throws -> Void
    public let syncNow: () -> Void
    public let deleteCloudData: () -> Void
    public let selectSyncFolder: () -> Void
    public let openSyncFolder: () -> Void
    public let removeSyncDevice: (String) -> Void
    private let defaultClipboardCacheDirectory: URL
    private let presentation: ToolModulePresentation
    @State private var translationAPIKey: String
    @State private var translationModel: String
    @State private var translationEndpointURLString: String
    @State private var isTranslationAPIKeyRevealed: Bool
    @State private var translationAPIKeyIsDirty: Bool
    @State private var translationSaveMessage: String?
    @State private var superRightClickLongPressMilliseconds: Double
    @State private var superRightClickSaveMessage: String?
    @State private var windowLayoutIsEnabled: Bool
    @State private var windowLayoutEnabledModes: Set<WindowLayoutMode>
    @State private var windowLayoutModeShortcuts: [WindowLayoutModeShortcuts]
    @State private var windowLayoutSaveMessage: String?
    @State private var appearanceMode: AppAppearanceMode
    @State private var appearanceSaveMessage: String?
    @State private var syncIsEnabled: Bool
    @State private var clipboardSyncScope: ClipboardSyncScope
    @State private var syncStorageLimit: SyncStorageLimit
    @State private var syncSaveMessage: String?

    /// 创建 `SettingsView`，保存传入依赖并建立初始状态。
    public init(
        selectedPane: Binding<SettingsPane>,
        settings: AppSettings,
        syncStatus: SyncStatus = .off,
        syncFolderPath: String? = nil,
        syncFolderIsUbiquitous: Bool? = nil,
        syncDevices: [SyncDeviceSummary] = [],
        translationCredentialUnavailable: Bool = false,
        permissionSummary: PermissionSummary,
        openSystemSettings: @escaping () -> Void,
        openPermissionSettings: @escaping (AppPermission) -> Void = { _ in },
        openClipboardStorageFolder: @escaping () -> Void = {},
        saveClipboardSettings: @escaping (ClipboardSettings) throws -> Void = { _ in },
        saveTranslationSettings: @escaping (TranslationSettings, Bool) async throws -> Void = { _, _ in },
        saveSuperRightClickSettings: @escaping (SuperRightClickSettings) throws -> Void = { _ in },
        saveWindowLayoutSettings: @escaping (WindowLayoutSettings) throws -> Void = { _ in },
        saveAppearanceMode: @escaping (AppAppearanceMode) throws -> Void = { _ in },
        saveSyncSettings: @escaping (SyncSettings) throws -> Void = { _ in },
        syncNow: @escaping () -> Void = {},
        deleteCloudData: @escaping () -> Void = {},
        selectSyncFolder: @escaping () -> Void = {},
        openSyncFolder: @escaping () -> Void = {},
        removeSyncDevice: @escaping (String) -> Void = { _ in },
        defaultClipboardCacheDirectory: URL = ClipboardCacheStorageDisplay.defaultDirectory,
        presentation: ToolModulePresentation = .window
    ) {
        self._selectedPane = selectedPane
        self.settings = settings
        self.syncStatus = syncStatus
        self.syncFolderPath = syncFolderPath
        self.syncFolderIsUbiquitous = syncFolderIsUbiquitous
        self.syncDevices = syncDevices
        self.translationCredentialUnavailable = translationCredentialUnavailable
        self.permissionSummary = permissionSummary
        self.openSystemSettings = openSystemSettings
        self.openPermissionSettings = openPermissionSettings
        self.openClipboardStorageFolder = openClipboardStorageFolder
        self.saveClipboardSettings = saveClipboardSettings
        self.saveTranslationSettings = saveTranslationSettings
        self.saveSuperRightClickSettings = saveSuperRightClickSettings
        self.saveWindowLayoutSettings = saveWindowLayoutSettings
        self.saveAppearanceMode = saveAppearanceMode
        self.saveSyncSettings = saveSyncSettings
        self.syncNow = syncNow
        self.deleteCloudData = deleteCloudData
        self.selectSyncFolder = selectSyncFolder
        self.openSyncFolder = openSyncFolder
        self.removeSyncDevice = removeSyncDevice
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.presentation = presentation
        self._translationAPIKey = State(initialValue: settings.translation.apiKey)
        self._translationModel = State(initialValue: settings.translation.model)
        self._translationEndpointURLString = State(initialValue: settings.translation.endpointURLString)
        self._isTranslationAPIKeyRevealed = State(initialValue: settings.translation.apiKey.isEmpty)
        self._translationAPIKeyIsDirty = State(initialValue: false)
        self._translationSaveMessage = State(initialValue: nil)
        self._superRightClickLongPressMilliseconds = State(
            initialValue: Double(settings.superRightClick.longPressMilliseconds)
        )
        self._superRightClickSaveMessage = State(initialValue: nil)
        self._windowLayoutIsEnabled = State(initialValue: settings.windowLayout.isEnabled)
        self._windowLayoutEnabledModes = State(initialValue: Set(settings.windowLayout.enabledModes))
        self._windowLayoutModeShortcuts = State(initialValue: settings.windowLayout.modeShortcuts)
        self._windowLayoutSaveMessage = State(initialValue: nil)
        self._appearanceMode = State(initialValue: settings.appearanceMode)
        self._appearanceSaveMessage = State(initialValue: nil)
        self._syncIsEnabled = State(initialValue: settings.sync.isEnabled)
        self._clipboardSyncScope = State(initialValue: settings.sync.clipboardScope)
        self._syncStorageLimit = State(initialValue: settings.sync.storageLimit)
        self._syncSaveMessage = State(initialValue: nil)
    }

    @ViewBuilder
    public var body: some View {
        Group {
            if presentation == .window {
                content
                    .liquidGlassWindowPanel(frame: .settings)
            } else {
                content
            }
        }
        .onChange(of: settings.translation.apiKey) { _, apiKey in
            guard !translationAPIKeyIsDirty else { return }
            translationAPIKey = apiKey
            isTranslationAPIKeyRevealed = apiKey.isEmpty
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            SettingsPaneToolbar(selection: $selectedPane)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(selectedPane.sections) { destination in
                        settingsSection(destination)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 2)
            }
            .id(selectedPane)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        MainWorkspaceModuleHeader(module: .settings)
    }

    @ViewBuilder
    private func settingsSection(_ destination: SettingsSectionDestination) -> some View {
        switch destination {
        case .system:
            systemSection
        case .shortcuts:
            shortcutsSection
        case .clipboard:
            clipboardSection
        case .translation:
            translationSection
        case .superRightClick:
            superRightClickSection
        case .windowLayout:
            windowLayoutSection
        case .permissions:
            permissionsSection
        case .sync:
            syncSection
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "快捷键", iconName: "keyboard") {
            SettingsRow(title: "设置页", value: settings.mainPanelShortcut.displayValue)
            SettingsRow(title: "剪贴板", value: settings.clipboardShortcut.displayValue)
            SettingsRow(title: "翻译", value: settings.reservedTool2Shortcut.displayValue)
            SettingsRow(title: "截图与录屏", value: settings.reservedTool3Shortcut.displayValue)
        }
    }

    private var clipboardSection: some View {
        SettingsSection(title: "剪贴板", iconName: "doc.on.clipboard") {
            ClipboardSettingsEditor(
                currentSettings: settings.clipboard,
                defaultCacheDirectory: defaultClipboardCacheDirectory,
                openStorageFolder: openClipboardStorageFolder
            )
        }
    }

    private var translationSection: some View {
        SettingsSection(title: "翻译", iconName: "character.book.closed") {
            TranslationSettingsEditor(
                currentSettings: settings.translation,
                credentialUnavailable: translationCredentialUnavailable,
                apiKey: Binding(
                    get: { translationAPIKey },
                    set: { value in
                        translationAPIKey = value
                        translationAPIKeyIsDirty = true
                    }
                ),
                model: $translationModel,
                endpointURLString: $translationEndpointURLString,
                isAPIKeyRevealed: $isTranslationAPIKeyRevealed,
                saveMessage: $translationSaveMessage,
                saveTranslationSettings: { settings in
                    try await saveTranslationSettings(settings, translationAPIKeyIsDirty)
                    translationAPIKeyIsDirty = false
                }
            )
        }
    }

    private var syncSection: some View {
        SettingsSection(title: "数据与同步", iconName: "icloud") {
            SyncSettingsEditor(
                currentSettings: settings.sync,
                status: syncStatus,
                folderPath: syncFolderPath,
                folderIsUbiquitous: syncFolderIsUbiquitous,
                devices: syncDevices,
                isEnabled: $syncIsEnabled,
                clipboardScope: $clipboardSyncScope,
                storageLimit: $syncStorageLimit,
                saveMessage: $syncSaveMessage,
                saveSettings: saveSyncSettings,
                syncNow: syncNow,
                deleteCloudData: deleteCloudData,
                selectFolder: selectSyncFolder,
                openFolder: openSyncFolder,
                removeDevice: removeSyncDevice
            )
        }
    }

    private var superRightClickSection: some View {
        SettingsSection(title: "超级右键", iconName: "cursorarrow.rays") {
            SuperRightClickSettingsEditor(
                currentSettings: settings.superRightClick,
                longPressMilliseconds: $superRightClickLongPressMilliseconds,
                saveMessage: $superRightClickSaveMessage,
                saveSuperRightClickSettings: saveSuperRightClickSettings
            )
        }
    }

    private var windowLayoutSection: some View {
        SettingsSection(title: "窗口布局", iconName: "rectangle.3.group") {
            WindowLayoutSettingsEditor(
                currentSettings: settings.windowLayout,
                reservedShortcuts: [
                    settings.mainPanelShortcut,
                    settings.clipboardShortcut,
                    settings.reservedTool2Shortcut,
                    settings.reservedTool3Shortcut
                ],
                isEnabled: $windowLayoutIsEnabled,
                enabledModes: $windowLayoutEnabledModes,
                modeShortcuts: $windowLayoutModeShortcuts,
                saveMessage: $windowLayoutSaveMessage,
                saveWindowLayoutSettings: saveWindowLayoutSettings
            )
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: "权限", iconName: "lock.shield") {
            PermissionStatusRow(
                title: "辅助功能",
                isEnabled: permissionSummary.hasAccessibility,
                permission: .accessibility,
                openPermissionSettings: openPermissionSettings
            )
            PermissionStatusRow(
                title: "输入监控",
                isEnabled: permissionSummary.hasInputMonitoring,
                permission: .inputMonitoring,
                openPermissionSettings: openPermissionSettings
            )
            PermissionStatusRow(
                title: "自动粘贴",
                isEnabled: permissionSummary.canPasteAutomatically,
                permission: .postEvent,
                openPermissionSettings: openPermissionSettings
            )
            PermissionStatusRow(
                title: "屏幕与系统音频录制",
                isEnabled: permissionSummary.canCaptureScreen,
                permission: .screenRecording,
                openPermissionSettings: openPermissionSettings
            )
        }
    }

    private var systemSection: some View {
        SettingsSection(title: "系统", iconName: "gearshape") {
            AppearanceSettingsEditor(
                currentMode: settings.appearanceMode,
                selectedMode: $appearanceMode,
                saveMessage: $appearanceSaveMessage,
                saveAppearanceMode: saveAppearanceMode
            )

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            Button(action: openSystemSettings) {
                Label("打开系统设置", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: MacToolsControlMetrics.settingsRowButtonMinimumHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
            .liquidGlassButtonStyle(cornerRadius: 14, showsIdleSurface: false)
        }
    }
}
