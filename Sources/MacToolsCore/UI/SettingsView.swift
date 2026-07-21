import AppKit
import SwiftUI

public struct SettingsView: View {
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
    public let confirmCloudAccountSwitch: () -> Void
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

    public init(
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
        confirmCloudAccountSwitch: @escaping () -> Void = {},
        selectSyncFolder: @escaping () -> Void = {},
        openSyncFolder: @escaping () -> Void = {},
        removeSyncDevice: @escaping (String) -> Void = { _ in },
        defaultClipboardCacheDirectory: URL = ClipboardCacheStorageDisplay.defaultDirectory,
        presentation: ToolModulePresentation = .window
    ) {
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
        self.confirmCloudAccountSwitch = confirmCloudAccountSwitch
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
        GeometryReader { geometry in
            let innerWidth = max(0, geometry.size.width - 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    settingsColumns(availableWidth: innerWidth)
                        .liquidGlassGroup(spacing: 14)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        MainWorkspaceModuleHeader(module: .settings)
    }

    @ViewBuilder
    private func settingsColumns(availableWidth: CGFloat) -> some View {
        Group {
            switch SettingsPageLayout.columnArrangement(for: availableWidth) {
            case .twoColumns:
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: SettingsPageLayout.columnSpacing) {
                        primarySettingsColumn
                            .frame(
                                minWidth: SettingsPageLayout.primaryColumnMinimumWidth,
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                        secondarySettingsColumn
                            .frame(
                                minWidth: SettingsPageLayout.secondaryColumnMinimumWidth,
                                maxWidth: .infinity,
                                alignment: .topLeading
                            )
                    }

                    windowLayoutSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 14) {
                    primarySettingsColumn
                    secondarySettingsColumn
                    windowLayoutSection
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var primarySettingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            shortcutsSection
            clipboardSection
            superRightClickSection
            permissionsSection
        }
    }

    private var secondarySettingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            translationSection
            syncSection
            systemSection
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

enum SyncFolderOpenDecision: Equatable {
    case openFolder
    case showFolderSelectionRequired
}

enum FolderOpenInteraction {
    static func openClipboardStorage(openFolder: () -> Void) {
        openFolder()
    }

    static func openSyncFolder(
        folderPath: String?,
        openFolder: () -> Void
    ) -> SyncFolderOpenDecision {
        guard let folderPath, !folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .showFolderSelectionRequired
        }

        openFolder()
        return .openFolder
    }
}

private struct SyncSettingsEditor: View {
    let currentSettings: SyncSettings
    let status: SyncStatus
    let folderPath: String?
    let folderIsUbiquitous: Bool?
    let devices: [SyncDeviceSummary]
    @Binding var isEnabled: Bool
    @Binding var clipboardScope: ClipboardSyncScope
    @Binding var storageLimit: SyncStorageLimit
    @Binding var saveMessage: String?
    let saveSettings: (SyncSettings) throws -> Void
    let syncNow: () -> Void
    let deleteCloudData: () -> Void
    let selectFolder: () -> Void
    let openFolder: () -> Void
    let removeDevice: (String) -> Void
    @State private var isDeleteConfirmationPresented = false
    @State private var isFolderSelectionRequiredPresented = false
    @State private var devicePendingRemoval: SyncDeviceSummary?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("iCloud Drive 同步")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Text(status.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 10)

                Toggle("iCloud Drive 同步", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(Text("iCloud Drive 同步"))
                    .disabled(folderPath == nil || status == .protocolIncompatible)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            if !devices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("同步设备")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    ForEach(devices) { device in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                                    .lineLimit(1)

                                Text(device.isCurrentDevice ? "本机" : lastSeenText(for: device))
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
                            }

                            Spacer(minLength: 8)

                            if !device.isCurrentDevice {
                                Button("移除", role: .destructive) {
                                    devicePendingRemoval = device
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                Divider()
                    .overlay(MacToolsGlassTheme.divider)
                    .opacity(0.9)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("同步文件夹")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textPrimary)

                        Text(folderPath ?? "尚未选择")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(MacToolsGlassTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if folderPath != nil, folderIsUbiquitous == false {
                            Text("普通文件夹 · 未确认由 iCloud Drive 管理")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 8)

                    Button(folderPath == nil ? "选择" : "更换", action: selectFolder)
                        .font(.system(size: 12, weight: .medium))
                }

                if let usage = status.storageUsage {
                    HStack(spacing: 6) {
                        Text(Self.byteCountFormatter.string(fromByteCount: usage.usedBytes))
                        Text("/")
                        Text(Self.byteCountFormatter.string(fromByteCount: usage.capacityBytes))
                        Spacer(minLength: 8)
                        Text("普通历史 \(usage.ordinaryHistoryCount) / 500")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("剪贴板范围")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Spacer(minLength: 10)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    }
                }

                Picker("剪贴板同步范围", selection: scopeBinding) {
                    ForEach(ClipboardSyncScope.allCases, id: \.self) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(!isEnabled || folderPath == nil)

                HStack(spacing: 10) {
                    Text("同步空间")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Spacer(minLength: 10)

                    Picker("同步空间上限", selection: storageLimitBinding) {
                        ForEach(SyncStorageLimit.allCases) { limit in
                            Text(limit.displayName).tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .disabled(!isEnabled || folderPath == nil)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            HStack(spacing: 8) {
                Button("立即同步", action: syncNow)
                    .disabled(!isEnabled || folderPath == nil)

                Button("打开文件夹", action: handleOpenFolder)

                Spacer(minLength: 8)

                Button("清空同步数据", role: .destructive) {
                    isDeleteConfirmationPresented = true
                }
                .disabled(!isEnabled || folderPath == nil)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .onChange(of: currentSettings) { _, settings in
            isEnabled = settings.isEnabled
            clipboardScope = settings.clipboardScope
            storageLimit = settings.storageLimit
        }
        .alert("清空 MacTools 同步数据？", isPresented: $isDeleteConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive, action: deleteCloudData)
        } message: {
            Text("所有设备会忽略旧同步快照；每台 Mac 的本地数据会保留。")
        }
        .alert(
            "移除同步设备？",
            isPresented: Binding(
                get: { devicePendingRemoval != nil },
                set: { if !$0 { devicePendingRemoval = nil } }
            ),
            presenting: devicePendingRemoval
        ) { device in
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                removeDevice(device.id)
                devicePendingRemoval = nil
            }
        } message: { device in
            Text("移除“\(device.name)”后，该设备重新上线时会以新设备身份加入；设备本地数据不会删除。")
        }
        .alert("需要先选择文件夹", isPresented: $isFolderSelectionRequiredPresented) {
            Button("知道了", role: .cancel) {}
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                let previous = isEnabled
                isEnabled = newValue
                save(previousEnabled: previous, previousScope: clipboardScope)
            }
        )
    }

    private var scopeBinding: Binding<ClipboardSyncScope> {
        Binding(
            get: { clipboardScope },
            set: { newValue in
                let previous = clipboardScope
                clipboardScope = newValue
                save(previousEnabled: isEnabled, previousScope: previous)
            }
        )
    }

    private var storageLimitBinding: Binding<SyncStorageLimit> {
        Binding(
            get: { storageLimit },
            set: { newValue in
                let previous = storageLimit
                storageLimit = newValue
                save(
                    previousEnabled: isEnabled,
                    previousScope: clipboardScope,
                    previousStorageLimit: previous
                )
            }
        )
    }

    private var statusColor: Color {
        switch status {
        case .synced:
            return .green
        case .waitingForDownload, .syncing:
            return .orange
        case .capacityFull, .folderUnavailable, .protocolIncompatible, .failed:
            return .red
        case .off, .unconfigured:
            return MacToolsGlassTheme.textTertiary
        }
    }

    private func handleOpenFolder() {
        switch FolderOpenInteraction.openSyncFolder(
            folderPath: folderPath,
            openFolder: openFolder
        ) {
        case .openFolder:
            break
        case .showFolderSelectionRequired:
            isFolderSelectionRequiredPresented = true
        }
    }

    private func save(
        previousEnabled: Bool,
        previousScope: ClipboardSyncScope,
        previousStorageLimit: SyncStorageLimit? = nil
    ) {
        do {
            try saveSettings(
                SyncSettings(
                    isEnabled: isEnabled,
                    clipboardScope: clipboardScope,
                    storageLimit: storageLimit
                )
            )
            saveMessage = "已保存"
        } catch {
            isEnabled = previousEnabled
            clipboardScope = previousScope
            if let previousStorageLimit { storageLimit = previousStorageLimit }
            saveMessage = "保存失败"
        }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private func lastSeenText(for device: SyncDeviceSummary) -> String {
        guard let date = device.lastUpdatedAt else { return "尚未完成同步" }
        return "最近同步 \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct AppearanceSettingsEditor: View {
    let currentMode: AppAppearanceMode
    @Binding var selectedMode: AppAppearanceMode
    @Binding var saveMessage: String?
    let saveAppearanceMode: (AppAppearanceMode) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("外观")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Spacer(minLength: 10)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Picker("外观", selection: selectionBinding) {
                ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("外观模式"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .onChange(of: currentMode) { _, mode in
            selectedMode = mode
        }
    }

    private var selectionBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { selectedMode },
            set: { mode in
                selectedMode = mode
                do {
                    try saveAppearanceMode(mode)
                    saveMessage = "已保存"
                } catch {
                    selectedMode = currentMode
                    saveMessage = "保存失败"
                }
            }
        )
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let iconName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }

            VStack(spacing: 0) {
                content
            }
            .liquidGlassModule(cornerRadius: 22)
            .liquidGlassGroup(spacing: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct ClipboardSettingsEditor: View {
    let currentSettings: ClipboardSettings
    let defaultCacheDirectory: URL
    let openStorageFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StatusRow(title: "记录状态", isEnabled: currentSettings.isRecordingEnabled, enabledTitle: "已启用", disabledTitle: "未启用")
            SettingsRow(title: "历史上限", value: "\(currentSettings.maxHistoryCount) 条")

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("统一存储")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Text(cacheStorageDisplay)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cacheStorageDisplay)
                }

                Spacer(minLength: 10)
                HStack(spacing: 6) {
                    Text("由 MacTools 管理")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textSecondary)

                    Button {
                        FolderOpenInteraction.openClipboardStorage(openFolder: openStorageFolder)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(
                                width: MacToolsControlMetrics.inlineIconSize.width,
                                height: MacToolsControlMetrics.inlineIconSize.height
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .help("打开统一存储文件夹")
                    .accessibilityLabel(Text("打开统一存储文件夹"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            SettingsRow(title: "图片对象", value: "按内容去重 · 自动回收")
        }
    }

    private var cacheStorageDisplay: String {
        ClipboardCacheStorageDisplay.displayPath(
            configuredPath: "",
            defaultDirectory: defaultCacheDirectory
        )
    }
}

private struct SuperRightClickSettingsEditor: View {
    let currentSettings: SuperRightClickSettings
    @Binding var longPressMilliseconds: Double
    @Binding var saveMessage: String?
    let saveSuperRightClickSettings: (SuperRightClickSettings) throws -> Void
    @State private var isEditingLongPressMilliseconds = false
    @State private var isCommittingLongPressMilliseconds = false

    private var normalizedMilliseconds: Int {
        SuperRightClickResponseSpeed.committedMilliseconds(forSliderValue: longPressMilliseconds)
    }

    private var sliderRange: ClosedRange<Double> {
        let lowerBound = Double(SuperRightClickResponseSpeed.minimumMilliseconds)
        let upperBound = Double(SuperRightClickResponseSpeed.maximumMilliseconds)
        return lowerBound...upperBound
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusRow(title: "状态", isEnabled: currentSettings.isEnabled, enabledTitle: "已启用", disabledTitle: "未启用")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("长按毫秒响应")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textPrimary)

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(spacing: 8) {
                        Slider(
                            value: $longPressMilliseconds,
                            in: sliderRange,
                            onEditingChanged: handleSliderEditingChanged(_:)
                        )
                        .tint(MacToolsGlassTheme.activeBlue)
                        .frame(maxWidth: 260)
                        .accessibilityLabel(Text("长按毫秒响应"))
                        .accessibilityValue(Text(SuperRightClickResponseSpeed.displayValue(for: normalizedMilliseconds)))

                        HStack {
                            ForEach(SuperRightClickResponseSpeed.markerMilliseconds, id: \.self) { milliseconds in
                                Text(SuperRightClickResponseSpeed.displayValue(for: milliseconds))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                                if milliseconds != SuperRightClickResponseSpeed.maximumMilliseconds {
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: 260)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .onChange(of: longPressMilliseconds) {
            guard !isCommittingLongPressMilliseconds else {
                isCommittingLongPressMilliseconds = false
                return
            }

            if !isEditingLongPressMilliseconds {
                commitSliderValue()
            }
        }
    }

    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isEditingLongPressMilliseconds = isEditing
        if !isEditing {
            commitSliderValue()
        }
    }

    private func commitSliderValue() {
        let milliseconds = normalizedMilliseconds
        if Int(longPressMilliseconds) != milliseconds {
            isCommittingLongPressMilliseconds = true
            longPressMilliseconds = Double(milliseconds)
        }

        do {
            try saveSuperRightClickSettings(
                SuperRightClickSettings(
                    isEnabled: currentSettings.isEnabled,
                    longPressMilliseconds: milliseconds
                )
            )
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }
}

private struct WindowLayoutSettingsEditor: View {
    let currentSettings: WindowLayoutSettings
    let reservedShortcuts: [HotKeyBinding]
    @Binding var isEnabled: Bool
    @Binding var enabledModes: Set<WindowLayoutMode>
    @Binding var modeShortcuts: [WindowLayoutModeShortcuts]
    @Binding var saveMessage: String?
    let saveWindowLayoutSettings: (WindowLayoutSettings) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("状态")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Spacer()

                Text(saveMessage ?? "已保存")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 50, alignment: .trailing)
                    .opacity(saveMessage == nil ? 0 : 1)

                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    sectionHeader("面板动作")
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 4)

                ForEach(Array(WindowLayoutSettingsLayout.modeGroups.enumerated()), id: \.element.id) { index, group in
                    modeGroupRow(group)

                    if index != WindowLayoutSettingsLayout.modeGroups.count - 1 {
                        Divider()
                            .overlay(MacToolsGlassTheme.divider)
                            .opacity(0.7)
                            .padding(.leading, 86)
                    }
                }
            }
            .disabled(!isEnabled)
        }
        .onChange(of: currentSettings) { _, settings in
            isEnabled = settings.isEnabled
            enabledModes = Set(settings.enabledModes)
            modeShortcuts = settings.modeShortcuts
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                save()
            }
        )
    }

    private func modeGroupRow(_ group: WindowLayoutModeGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(group.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacToolsGlassTheme.textTertiary)
                .frame(width: 62, alignment: .leading)
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 8) {
                ForEach(group.modes) { mode in
                    WindowLayoutModeActionCell(
                        mode: mode,
                        isPresentedInPanel: enabledModes.contains(mode),
                        isSettingsEnabled: isEnabled,
                        shortcut: shortcuts(for: mode).first,
                        togglePanelVisibility: { shouldShow in
                            setMode(mode, isEnabled: shouldShow)
                        },
                        updateShortcut: { shortcut in
                            replaceShortcut(for: mode, with: shortcut)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func setMode(_ mode: WindowLayoutMode, isEnabled: Bool) {
        if isEnabled {
            enabledModes.insert(mode)
        } else {
            enabledModes.remove(mode)
        }
        save()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MacToolsGlassTheme.textTertiary)
    }

    private func shortcuts(for mode: WindowLayoutMode) -> [HotKeyBinding] {
        modeShortcuts.first { $0.mode == mode }?.shortcuts ?? []
    }

    @discardableResult
    private func replaceShortcut(for mode: WindowLayoutMode, with shortcut: HotKeyBinding?) -> Bool {
        guard let shortcut else {
            modeShortcuts = draftSettings.replacingPrimaryShortcut(for: mode, with: nil).modeShortcuts
            save()
            return true
        }

        guard shortcut.isUsableGlobalShortcut else {
            saveMessage = "请先输入快捷键"
            return false
        }

        let shortcutsInOtherModes = Set(
            modeShortcuts
                .filter { $0.mode != mode }
                .flatMap(\.shortcuts)
        )
        guard !reservedShortcuts.contains(shortcut), !shortcutsInOtherModes.contains(shortcut) else {
            saveMessage = "快捷键已存在"
            return false
        }

        modeShortcuts = draftSettings.replacingPrimaryShortcut(for: mode, with: shortcut).modeShortcuts
        save()
        return true
    }

    private func save() {
        let updatedSettings = draftSettings
        modeShortcuts = updatedSettings.modeShortcuts

        do {
            try saveWindowLayoutSettings(updatedSettings)
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }

    private var draftSettings: WindowLayoutSettings {
        WindowLayoutSettings(
            isEnabled: isEnabled,
            enabledModes: WindowLayoutMode.allCases.filter { enabledModes.contains($0) },
            modeShortcuts: modeShortcuts
        )
    }
}

private struct WindowLayoutModeActionCell: View {
    let mode: WindowLayoutMode
    let isPresentedInPanel: Bool
    let isSettingsEnabled: Bool
    let shortcut: HotKeyBinding?
    let togglePanelVisibility: (Bool) -> Void
    let updateShortcut: (HotKeyBinding?) -> Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                WindowLayoutModePreviewIcon(mode: mode)
                    .frame(width: 36, height: 24)

                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { isPresentedInPanel },
                        set: togglePanelVisibility
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isSettingsEnabled)
                .help(isPresentedInPanel ? "从面板隐藏" : "在面板显示")
            }

            shortcutEditor
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .opacity(isSettingsEnabled ? (isPresentedInPanel ? 1 : 0.62) : 0.45)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? MacToolsGlassTheme.activeBlue.opacity(0.12) : Color.white.opacity(0.050))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHovered ? MacToolsGlassTheme.activeBlue.opacity(0.34) : MacToolsGlassTheme.border, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var shortcutEditor: some View {
        HStack(spacing: 8) {
            WindowLayoutShortcutCaptureField(
                shortcut: shortcut,
                placeholder: "按下快捷键",
                onShortcutChange: updateShortcut
            )
            .frame(height: 32)
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MacToolsGlassTheme.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MacToolsGlassTheme.border, lineWidth: 1)
            )

            Button {
                _ = updateShortcut(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(
                        width: MacToolsControlMetrics.inlineIconSize.width,
                        height: MacToolsControlMetrics.inlineIconSize.height
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(shortcut == nil ? MacToolsGlassTheme.textDisabled : MacToolsGlassTheme.textTertiary)
            .disabled(shortcut == nil || !isSettingsEnabled)
            .help("删除快捷键")
            .accessibilityLabel(Text("删除快捷键"))
        }
    }
}

private struct WindowLayoutShortcutCaptureField: NSViewRepresentable {
    let shortcut: HotKeyBinding?
    let placeholder: String
    let onShortcutChange: (HotKeyBinding?) -> Bool

    func makeNSView(context: Context) -> WindowLayoutShortcutCaptureTextField {
        let field = WindowLayoutShortcutCaptureTextField()
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ nsView: WindowLayoutShortcutCaptureTextField, context: Context) {
        nsView.configure(
            shortcut: shortcut,
            placeholder: placeholder,
            onShortcutChange: onShortcutChange
        )
    }
}

final class WindowLayoutShortcutCaptureTextField: NSTextField {
    private var currentShortcut: HotKeyBinding?
    private var onShortcutChange: (HotKeyBinding?) -> Bool = { _ in true }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 30)
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        focusRingType = .none
        cell = VerticallyCenteredTextFieldCell()
        alignment = .center
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = NSColor.white.withAlphaComponent(0.78)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        shortcut: HotKeyBinding?,
        placeholder: String,
        onShortcutChange: @escaping (HotKeyBinding?) -> Bool
    ) {
        currentShortcut = shortcut
        self.onShortcutChange = onShortcutChange
        placeholderString = placeholder
        let displayValue = shortcut?.displayValue ?? ""
        if stringValue != displayValue {
            stringValue = displayValue
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        _ = capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        return capture(event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, Self.modifierNames(from: event).isEmpty {
            if onShortcutChange(nil) {
                currentShortcut = nil
                stringValue = ""
            }
            return true
        }

        guard let shortcut = Self.shortcut(from: event) else {
            NSSound.beep()
            return true
        }

        if onShortcutChange(shortcut) {
            currentShortcut = shortcut
            stringValue = shortcut.displayValue
        } else {
            stringValue = currentShortcut?.displayValue ?? ""
        }
        return true
    }

    private static func shortcut(from event: NSEvent) -> HotKeyBinding? {
        let modifiers = modifierNames(from: event)
        guard !modifiers.isEmpty, let key = keyName(from: event) else {
            return nil
        }
        return HotKeyBinding(key: key, modifiers: modifiers)
    }

    private static func modifierNames(from event: NSEvent) -> [String] {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: [String] = []
        if flags.contains(.control) {
            modifiers.append("Control")
        }
        if flags.contains(.option) {
            modifiers.append("Option")
        }
        if flags.contains(.shift) {
            modifiers.append("Shift")
        }
        if flags.contains(.command) {
            modifiers.append("Command")
        }
        return modifiers
    }

    private static func keyName(from event: NSEvent) -> String? {
        if let keyName = keyNamesByCode[event.keyCode] {
            return keyName
        }

        guard let character = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !character.isEmpty
        else {
            return nil
        }

        if character == " " {
            return "Space"
        }

        return character.count == 1 ? character.uppercased() : nil
    }

    private static let keyNamesByCode: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]
}

private final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(super.drawingRect(forBounds: rect), in: rect)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(super.titleRect(forBounds: rect), in: rect)
    }

    private func centeredRect(_ textRect: NSRect, in bounds: NSRect) -> NSRect {
        var rect = textRect
        rect.size.height = min(bounds.height, ceil(cellSize(forBounds: bounds).height))
        rect.origin.y = bounds.origin.y + (bounds.height - rect.height) / 2
        return rect
    }
}

private struct WindowLayoutModePreviewIcon: View {
    let mode: WindowLayoutMode

    var body: some View {
        WindowLayoutPreviewIcon(segments: [mode.previewSegment])
    }
}

private struct WindowLayoutPreviewIcon: View {
    let segments: [WindowLayoutPreviewSegment]

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let screen = WindowLayoutPreviewGeometry.screenFrame(in: bounds)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: screen.minX, y: screen.minY)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.34), lineWidth: 1)
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: screen.minX, y: screen.minY)

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let target = WindowLayoutPreviewGeometry.targetFrame(for: segment, in: bounds)

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(MacToolsGlassTheme.activeBlue.opacity(index == 0 ? 0.82 : 0.58))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .strokeBorder(MacToolsGlassTheme.activeBlue.opacity(0.88), lineWidth: 0.8)
                        )
                        .frame(
                            width: target.width,
                            height: target.height
                        )
                        .offset(
                            x: target.minX,
                            y: target.minY
                        )
                }
            }
        }
        .aspectRatio(1.42, contentMode: .fit)
    }
}

private struct TranslationSettingsEditor: View {
    let currentSettings: TranslationSettings
    let credentialUnavailable: Bool
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var endpointURLString: String
    @Binding var isAPIKeyRevealed: Bool
    @Binding var saveMessage: String?
    let saveTranslationSettings: (TranslationSettings) async throws -> Void
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "服务", value: "阿里云百炼")
            SettingsRow(title: "状态", value: credentialStatusText)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Spacer(minLength: 12)

                    apiKeyControl
                        .frame(maxWidth: 240, alignment: .trailing)
                }

                Divider()
                    .overlay(MacToolsGlassTheme.divider)
                    .opacity(0.9)

                labeledTextField(title: "模型", text: $model)

                Divider()
                    .overlay(MacToolsGlassTheme.divider)
                    .opacity(0.9)

                labeledTextField(title: "Endpoint", text: $endpointURLString)

                HStack(spacing: 10) {
                    Button(action: save) {
                        Label("保存", systemImage: "tray.and.arrow.down")
                            .font(.system(size: MacToolsControlMetrics.textActionFontSize, weight: .semibold))
                    }
                    .buttonStyle(GlassPrimaryButtonStyle(cornerRadius: 14))
                    .disabled(isSaving)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var credentialStatusText: String {
        if credentialUnavailable { return "Keychain 凭据不可访问" }
        return currentSettings.isConfigured ? "已安全保存" : "未配置"
    }

    @ViewBuilder
    private var apiKeyControl: some View {
        HStack(spacing: 8) {
            TranslationAPIKeyEditableField(
                text: $apiKey,
                isSecure: TranslationAPIKeyInputMode(isRevealed: isAPIKeyRevealed).usesSecureField,
                placeholder: "DASHSCOPE_API_KEY",
                onCopy: { didCopy in
                    saveMessage = didCopy ? "已复制 API Key" : "没有可复制的 API Key"
                },
                onPaste: { didPaste in
                    if didPaste {
                        isAPIKeyRevealed = true
                        saveMessage = "已粘贴 API Key"
                    } else {
                        saveMessage = "剪贴板没有 API Key"
                    }
                }
            )
            .frame(height: 22)
            .frame(minWidth: 92, maxWidth: .infinity, alignment: .trailing)
            .layoutPriority(1)

            apiKeyIconButton(
                systemName: isAPIKeyRevealed ? "eye.slash" : "eye",
                help: isAPIKeyRevealed ? "隐藏 API Key" : "显示 API Key"
            ) {
                isAPIKeyRevealed.toggle()
            }
        }
    }

    private func labeledTextField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            Spacer(minLength: 12)

            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(maxWidth: 190)
        }
    }

    private func apiKeyIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(
                    width: MacToolsControlMetrics.inlineIconSize.width,
                    height: MacToolsControlMetrics.inlineIconSize.height
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacToolsGlassTheme.textSecondary)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private func save() {
        let trimmedEndpoint = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmedEndpoint) != nil else {
            saveMessage = "Endpoint URL 无效"
            return
        }

        var updatedSettings = currentSettings
        updatedSettings.providerID = TranslationSettings.defaultProviderID
        updatedSettings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSettings.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSettings.endpointURLString = trimmedEndpoint

        isSaving = true
        saveMessage = "正在保存…"
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await saveTranslationSettings(updatedSettings)
                saveMessage = "已保存"
                if updatedSettings.isConfigured {
                    isAPIKeyRevealed = false
                }
            } catch {
                saveMessage = "保存失败"
            }
        }
    }
}

struct TranslationAPIKeyInputMode {
    let isRevealed: Bool

    var usesSecureField: Bool {
        !isRevealed
    }
}

enum TranslationAPIKeyKeyboardCommand: Equatable {
    case copy
    case paste

    static func command(forKeyCode keyCode: UInt16, isCommandPressed: Bool) -> TranslationAPIKeyKeyboardCommand? {
        command(
            forKeyCode: keyCode,
            charactersIgnoringModifiers: nil,
            isCommandPressed: isCommandPressed
        )
    }

    static func command(
        forKeyCode keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        isCommandPressed: Bool
    ) -> TranslationAPIKeyKeyboardCommand? {
        guard isCommandPressed else {
            return nil
        }

        switch charactersIgnoringModifiers?.lowercased() {
        case "c":
            return .copy
        case "v":
            return .paste
        default:
            break
        }

        switch keyCode {
        case 8:
            return .copy
        case 9:
            return .paste
        default:
            return nil
        }
    }

    static func copyableString(from apiKey: String) -> String? {
        normalizedAPIKey(from: apiKey)
    }

    static func pastedAPIKey(from pasteboardString: String?) -> String? {
        guard let pasteboardString else {
            return nil
        }

        return normalizedAPIKey(from: pasteboardString)
    }

    private static func normalizedAPIKey(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

private struct TranslationAPIKeyEditableField: NSViewRepresentable {
    @Binding var text: String
    let isSecure: Bool
    let placeholder: String
    let onCopy: (Bool) -> Void
    let onPaste: (Bool) -> Void

    func makeNSView(context: Context) -> TranslationAPIKeyNativeInputView {
        let view = TranslationAPIKeyNativeInputView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: TranslationAPIKeyNativeInputView, context: Context) {
        nsView.configure(
            text: text,
            isSecure: isSecure,
            placeholder: placeholder,
            onTextChange: { text = $0 },
            onCopy: onCopy,
            onPaste: onPaste
        )
    }
}

private final class TranslationAPIKeyNativeInputView: NSView, NSTextFieldDelegate {
    private var field: NSTextField?
    private var monitor: Any?
    private var isConfiguredAsSecure = false
    private var isEditing = false
    private var onTextChange: (String) -> Void = { _ in }
    private var onCopy: (Bool) -> Void = { _ in }
    private var onPaste: (Bool) -> Void = { _ in }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: 22)
    }

    func configure(
        text: String,
        isSecure: Bool,
        placeholder: String,
        onTextChange: @escaping (String) -> Void,
        onCopy: @escaping (Bool) -> Void,
        onPaste: @escaping (Bool) -> Void
    ) {
        self.onTextChange = onTextChange
        self.onCopy = onCopy
        self.onPaste = onPaste

        if field == nil || isConfiguredAsSecure != isSecure {
            replaceField(isSecure: isSecure)
        }

        field?.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.32)
            ]
        )
        if field?.stringValue != text {
            field?.stringValue = text
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    deinit {
        removeMonitor()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        isEditing = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        isEditing = false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }

        onTextChange(field.stringValue)
    }

    private func replaceField(isSecure: Bool) {
        let previousField = field
        let replacement: NSTextField = isSecure ? TranslationAPIKeySecureTextField() : TranslationAPIKeyTextField()
        configureField(replacement)

        previousField?.removeFromSuperview()
        field = replacement
        isConfiguredAsSecure = isSecure
        isEditing = false

        addSubview(replacement)
        NSLayoutConstraint.activate([
            replacement.leadingAnchor.constraint(equalTo: leadingAnchor),
            replacement.trailingAnchor.constraint(equalTo: trailingAnchor),
            replacement.topAnchor.constraint(equalTo: topAnchor),
            replacement.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        invalidateIntrinsicContentSize()
    }

    private func configureField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = NSColor.white.withAlphaComponent(0.78)
        field.alignment = .right
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.lineBreakMode = .byTruncatingMiddle
        field.delegate = self
        if let commandField = field as? TranslationAPIKeyCommandHandlingField {
            commandField.onCommandKeyEquivalent = { [weak self] event in
                self?.handleKeyDown(event) ?? false
            }
        }
    }

    private func updateMonitor() {
        if window == nil {
            removeMonitor()
            return
        }

        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKeyDown(event) else {
                return event
            }

            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard
            isEditingAPIKeyField(),
            let command = TranslationAPIKeyKeyboardCommand.command(
                forKeyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                isCommandPressed: event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .contains(.command)
            )
        else {
            return false
        }

        switch command {
        case .copy:
            guard let copyableString = TranslationAPIKeyKeyboardCommand.copyableString(from: field?.stringValue ?? "") else {
                onCopy(false)
                return true
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyableString, forType: .string)
            onCopy(true)
            return true

        case .paste:
            guard let pastedAPIKey = TranslationAPIKeyKeyboardCommand.pastedAPIKey(
                from: NSPasteboard.general.string(forType: .string)
            ) else {
                onPaste(false)
                return true
            }

            field?.stringValue = pastedAPIKey
            onTextChange(pastedAPIKey)
            onPaste(true)
            return true
        }
    }

    private func isEditingAPIKeyField() -> Bool {
        if isEditing {
            return true
        }

        guard let field else {
            return false
        }

        if window?.firstResponder === field {
            return true
        }

        guard let editor = field.currentEditor() else {
            return false
        }

        return window?.firstResponder === editor
    }
}

private protocol TranslationAPIKeyCommandHandlingField: AnyObject {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)? { get set }
}

private final class TranslationAPIKeyTextField: NSTextField, TranslationAPIKeyCommandHandlingField {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommandKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onCommandKeyEquivalent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

private final class TranslationAPIKeySecureTextField: NSSecureTextField, TranslationAPIKeyCommandHandlingField {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommandKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onCommandKeyEquivalent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

private struct StatusRow: View {
    let title: String
    let isEnabled: Bool
    var enabledTitle = "已允许"
    var disabledTitle = "未授权"

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            Spacer()

            GlassStatusPill(
                isEnabled ? enabledTitle : disabledTitle,
                systemImage: isEnabled ? "checkmark" : "exclamationmark",
                color: MacToolsGlassTheme.statusColor(isEnabled: isEnabled)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let isEnabled: Bool
    let permission: AppPermission
    let openPermissionSettings: (AppPermission) -> Void

    var body: some View {
        if isEnabled {
            StatusRow(title: title, isEnabled: true)
        } else {
            Button {
                openPermissionSettings(permission)
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Spacer()

                    HStack(spacing: 6) {
                        Text("检查设置")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(MacToolsGlassTheme.warning)
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: MacToolsControlMetrics.settingsRowButtonMinimumHeight)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
            .liquidGlassButtonStyle(cornerRadius: 14, showsIdleSurface: false)
        }
    }
}
