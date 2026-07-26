// `SyncSettingsEditor` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import AppKit
import SwiftUI

/// 描述 `SyncFolderOpenDecision` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum SyncFolderOpenDecision: Equatable {
    case openFolder
    case showFolderSelectionRequired
}
/// 描述 `FolderOpenInteraction` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum FolderOpenInteraction {
    /// 触发打开本地剪贴板存储目录的系统操作。
    static func openClipboardStorage(openFolder: () -> Void) {
        openFolder()
    }

    /// 有已选路径时打开同步目录，否则要求界面提示先选择目录。
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

/// 封装 `SyncSettingsEditor` 在 SwiftUI 展示层中的值语义和相关操作。
struct SyncSettingsEditor: View {
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

    /// 根据目录是否已配置执行打开操作或展示选择提示。
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

    /// 组装当前同步草稿并交给外部保存闭包，错误转换为页面提示。
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

    /// 构建并返回 `lastSeenText` 对应的 SwiftUI 界面内容或展示状态。
    private func lastSeenText(for device: SyncDeviceSummary) -> String {
        guard let date = device.lastUpdatedAt else { return "尚未完成同步" }
        return "最近同步 \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
