import AppKit
import SwiftUI

public struct SettingsView: View {
    public let settings: AppSettings
    public let permissionSummary: PermissionSummary
    public let openSystemSettings: () -> Void
    public let openPermissionSettings: (AppPermission) -> Void
    public let saveClipboardSettings: (ClipboardSettings) throws -> Void
    public let saveTranslationSettings: (TranslationSettings) throws -> Void
    public let saveSuperRightClickSettings: (SuperRightClickSettings) throws -> Void
    public let saveWindowLayoutSettings: (WindowLayoutSettings) throws -> Void
    private let defaultClipboardCacheDirectory: URL
    private let presentation: ToolModulePresentation
    @State private var clipboardCacheStoragePath: String
    @State private var clipboardMaxCacheMegabytes: Int
    @State private var clipboardSaveMessage: String?
    @State private var translationAPIKey: String
    @State private var translationModel: String
    @State private var translationEndpointURLString: String
    @State private var isTranslationAPIKeyRevealed: Bool
    @State private var translationSaveMessage: String?
    @State private var superRightClickLongPressMilliseconds: Double
    @State private var superRightClickSaveMessage: String?
    @State private var windowLayoutIsEnabled: Bool
    @State private var windowLayoutEnabledModes: Set<WindowLayoutMode>
    @State private var windowLayoutModeShortcuts: [WindowLayoutModeShortcuts]
    @State private var windowLayoutSaveMessage: String?

    public init(
        settings: AppSettings,
        permissionSummary: PermissionSummary,
        openSystemSettings: @escaping () -> Void,
        openPermissionSettings: @escaping (AppPermission) -> Void = { _ in },
        saveClipboardSettings: @escaping (ClipboardSettings) throws -> Void = { _ in },
        saveTranslationSettings: @escaping (TranslationSettings) throws -> Void = { _ in },
        saveSuperRightClickSettings: @escaping (SuperRightClickSettings) throws -> Void = { _ in },
        saveWindowLayoutSettings: @escaping (WindowLayoutSettings) throws -> Void = { _ in },
        defaultClipboardCacheDirectory: URL = ClipboardCacheStorageDisplay.defaultDirectory,
        presentation: ToolModulePresentation = .window
    ) {
        self.settings = settings
        self.permissionSummary = permissionSummary
        self.openSystemSettings = openSystemSettings
        self.openPermissionSettings = openPermissionSettings
        self.saveClipboardSettings = saveClipboardSettings
        self.saveTranslationSettings = saveTranslationSettings
        self.saveSuperRightClickSettings = saveSuperRightClickSettings
        self.saveWindowLayoutSettings = saveWindowLayoutSettings
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.presentation = presentation
        self._clipboardCacheStoragePath = State(initialValue: settings.clipboard.cacheStoragePath)
        self._clipboardMaxCacheMegabytes = State(initialValue: settings.clipboard.maxCacheMegabytes)
        self._clipboardSaveMessage = State(initialValue: nil)
        self._translationAPIKey = State(initialValue: settings.translation.apiKey)
        self._translationModel = State(initialValue: settings.translation.model)
        self._translationEndpointURLString = State(initialValue: settings.translation.endpointURLString)
        self._isTranslationAPIKeyRevealed = State(initialValue: settings.translation.apiKey.isEmpty)
        self._translationSaveMessage = State(initialValue: nil)
        self._superRightClickLongPressMilliseconds = State(
            initialValue: Double(settings.superRightClick.longPressMilliseconds)
        )
        self._superRightClickSaveMessage = State(initialValue: nil)
        self._windowLayoutIsEnabled = State(initialValue: settings.windowLayout.isEnabled)
        self._windowLayoutEnabledModes = State(initialValue: Set(settings.windowLayout.enabledModes))
        self._windowLayoutModeShortcuts = State(initialValue: settings.windowLayout.modeShortcuts)
        self._windowLayoutSaveMessage = State(initialValue: nil)
    }

    @ViewBuilder
    public var body: some View {
        if presentation == .window {
            content
                .liquidGlassWindowPanel(frame: .settings)
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                settingsColumns
                    .liquidGlassGroup(spacing: 14)
            }
            .padding(22)
            .frame(maxWidth: 900, alignment: .topLeading)
        }
    }

    private var header: some View {
        MainWorkspaceModuleHeader(module: .settings)
    }

    private var settingsColumns: some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    primarySettingsColumn
                        .frame(width: 320, alignment: .topLeading)
                    secondarySettingsColumn
                        .frame(width: 440, alignment: .topLeading)
                }

                windowLayoutSection
                    .frame(width: 774, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 14) {
                primarySettingsColumn
                secondarySettingsColumn
                windowLayoutSection
            }
            .frame(maxWidth: 440, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var primarySettingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            shortcutsSection
            clipboardSection
            superRightClickSection
        }
    }

    private var secondarySettingsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            translationSection
            permissionsSection
            systemSection
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "快捷键", iconName: "keyboard") {
            SettingsRow(title: "设置页", value: settings.mainPanelShortcut.displayValue)
            SettingsRow(title: "剪贴板", value: settings.clipboardShortcut.displayValue)
            SettingsRow(title: "翻译", value: settings.reservedTool2Shortcut.displayValue)
            SettingsRow(title: "工具 3", value: settings.reservedTool3Shortcut.displayValue)
        }
    }

    private var clipboardSection: some View {
        SettingsSection(title: "剪贴板", iconName: "doc.on.clipboard") {
            ClipboardSettingsEditor(
                currentSettings: settings.clipboard,
                cacheStoragePath: $clipboardCacheStoragePath,
                maxCacheMegabytes: $clipboardMaxCacheMegabytes,
                saveMessage: $clipboardSaveMessage,
                defaultCacheDirectory: defaultClipboardCacheDirectory,
                saveClipboardSettings: saveClipboardSettings
            )
        }
    }

    private var translationSection: some View {
        SettingsSection(title: "翻译", iconName: "character.book.closed") {
            TranslationSettingsEditor(
                currentSettings: settings.translation,
                apiKey: $translationAPIKey,
                model: $translationModel,
                endpointURLString: $translationEndpointURLString,
                isAPIKeyRevealed: $isTranslationAPIKeyRevealed,
                saveMessage: $translationSaveMessage,
                saveTranslationSettings: saveTranslationSettings
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
        }
    }

    private var systemSection: some View {
        SettingsSection(title: "系统", iconName: "gearshape") {
            Button(action: openSystemSettings) {
                Label("打开系统设置", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(.black)
            .liquidGlassButtonStyle(cornerRadius: 14, showsIdleSurface: false)
        }
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
                    .foregroundStyle(Color.black.opacity(0.60))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.60))
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
                .foregroundStyle(.black)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.black.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

private struct ClipboardSettingsEditor: View {
    let currentSettings: ClipboardSettings
    @Binding var cacheStoragePath: String
    @Binding var maxCacheMegabytes: Int
    @Binding var saveMessage: String?
    let defaultCacheDirectory: URL
    let saveClipboardSettings: (ClipboardSettings) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            StatusRow(title: "记录状态", isEnabled: currentSettings.isRecordingEnabled)
            SettingsRow(title: "历史上限", value: "\(currentSettings.maxHistoryCount) 条")

            Divider()
                .opacity(0.18)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("存储位置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black)

                    Text(cacheStorageDisplay)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cacheStorageDisplay)
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    iconButton(systemName: "folder", help: "选择存储位置", action: chooseCacheStoragePath)

                    iconButton(
                        systemName: "arrow.uturn.backward",
                        help: "恢复默认位置",
                        action: resetCacheStoragePath
                    )
                    .disabled(cacheStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(cacheStoragePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .opacity(0.18)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text("缓存上限")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black)

                    Spacer(minLength: 10)

                    Text(ClipboardCacheLimit.displayValue(for: maxCacheMegabytes))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.58))
                }

                Picker("缓存上限", selection: cacheLimitBinding) {
                    ForEach(ClipboardCacheLimit.allowedMegabytes, id: \.self) { megabytes in
                        Text("\(megabytes)M").tag(megabytes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.58))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .onChange(of: currentSettings) { settings in
            cacheStoragePath = settings.cacheStoragePath
            maxCacheMegabytes = settings.maxCacheMegabytes
        }
    }

    private var cacheLimitBinding: Binding<Int> {
        Binding(
            get: { ClipboardCacheLimit.normalizedMegabytes(maxCacheMegabytes) },
            set: { newValue in
                maxCacheMegabytes = ClipboardCacheLimit.normalizedMegabytes(newValue)
                save()
            }
        )
    }

    private var cacheStorageDisplay: String {
        ClipboardCacheStorageDisplay.displayPath(
            configuredPath: cacheStoragePath,
            defaultDirectory: defaultCacheDirectory
        )
    }

    private func iconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.62))
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private func chooseCacheStoragePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择剪贴板图片缓存的存储位置"
        let currentPath = cacheStoragePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentPath.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: NSString(string: currentPath).expandingTildeInPath,
                isDirectory: true
            )
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        cacheStoragePath = selectedURL.path
        save()
    }

    private func resetCacheStoragePath() {
        cacheStoragePath = ""
        save()
    }

    private func save() {
        let updatedSettings = ClipboardSettings(
            isRecordingEnabled: currentSettings.isRecordingEnabled,
            maxHistoryCount: currentSettings.maxHistoryCount,
            maxCacheMegabytes: maxCacheMegabytes,
            cacheStoragePath: cacheStoragePath
        )

        do {
            try saveClipboardSettings(updatedSettings)
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
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
            SettingsRow(title: "状态", value: currentSettings.isEnabled ? "已启用" : "未启用")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("长按毫秒响应")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.black)

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.56))
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
                        .tint(Color(red: 0.29, green: 0.35, blue: 0.70))
                        .frame(maxWidth: 260)
                        .accessibilityLabel(Text("长按毫秒响应"))
                        .accessibilityValue(Text(SuperRightClickResponseSpeed.displayValue(for: normalizedMilliseconds)))

                        HStack {
                            ForEach(SuperRightClickResponseSpeed.markerMilliseconds, id: \.self) { milliseconds in
                                Text(SuperRightClickResponseSpeed.displayValue(for: milliseconds))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(0.60))

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
        .onChange(of: longPressMilliseconds) { _ in
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
                    .foregroundStyle(.black)

                Spacer()

                Text(saveMessage ?? "已保存")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.58))
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
                .opacity(0.18)

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
                            .opacity(0.12)
                            .padding(.leading, 86)
                    }
                }
            }
            .disabled(!isEnabled)
        }
        .onChange(of: currentSettings) { settings in
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
                .foregroundStyle(Color.black.opacity(0.52))
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
            .foregroundStyle(Color.black.opacity(0.56))
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
                    .frame(width: 32, height: 22)

                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
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
                .fill(Color.white.opacity(isHovered ? 0.32 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.black.opacity(isHovered ? 0.16 : 0.08), lineWidth: 1)
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
                    .fill(Color.white.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
            )

            Button {
                _ = updateShortcut(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black.opacity(shortcut == nil ? 0.18 : 0.46))
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

private final class WindowLayoutShortcutCaptureTextField: NSTextField {
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
        textColor = NSColor.black.withAlphaComponent(0.68)
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
        rect.origin.y = bounds.origin.y + floor((bounds.height - rect.height) / 2)
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
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.8)

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.black.opacity(segmentOpacity(at: index)))
                        .frame(
                            width: max(2, size.width * segment.width),
                            height: max(2, size.height * segment.height)
                        )
                        .offset(
                            x: size.width * segment.x,
                            y: size.height * segment.y
                        )
                }
            }
        }
        .aspectRatio(1.42, contentMode: .fit)
    }

    private func segmentOpacity(at index: Int) -> Double {
        switch index {
        case 0:
            return 0.52
        case 1:
            return 0.38
        default:
            return 0.28
        }
    }
}

private struct TranslationSettingsEditor: View {
    let currentSettings: TranslationSettings
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var endpointURLString: String
    @Binding var isAPIKeyRevealed: Bool
    @Binding var saveMessage: String?
    let saveTranslationSettings: (TranslationSettings) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "服务", value: "阿里云百炼")
            SettingsRow(title: "状态", value: currentSettings.isConfigured ? "已配置" : "未配置")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black)

                    Spacer(minLength: 12)

                    apiKeyControl
                        .frame(maxWidth: 240, alignment: .trailing)
                }

                Divider()
                    .opacity(0.18)

                labeledTextField(title: "模型", text: $model)

                Divider()
                    .opacity(0.18)

                labeledTextField(title: "Endpoint", text: $endpointURLString)

                HStack(spacing: 10) {
                    Button(action: save) {
                        Label("保存", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.black)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.58))
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
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
                .foregroundStyle(.black)

            Spacer(minLength: 12)

            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
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
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black.opacity(0.62))
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

        do {
            try saveTranslationSettings(updatedSettings)
            saveMessage = "已保存"
            if updatedSettings.isConfigured {
                isAPIKeyRevealed = false
            }
        } catch {
            saveMessage = "保存失败"
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

        field?.placeholderString = placeholder
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

    var body: some View {
        SettingsRow(title: title, value: isEnabled ? "已允许" : "未授权")
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let isEnabled: Bool
    let permission: AppPermission
    let openPermissionSettings: (AppPermission) -> Void

    var body: some View {
        if isEnabled {
            SettingsRow(title: title, value: "已允许")
        } else {
            Button {
                openPermissionSettings(permission)
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black)

                    Spacer()

                    HStack(spacing: 6) {
                        Text("检查设置")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.black.opacity(0.70))
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(Color.black.opacity(0.72))
            .liquidGlassButtonStyle(cornerRadius: 14, showsIdleSurface: false)
        }
    }
}
