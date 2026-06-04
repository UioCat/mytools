import AppKit
import SwiftUI

public struct SettingsView: View {
    public let settings: AppSettings
    public let permissionSummary: PermissionSummary
    public let openSystemSettings: () -> Void
    public let openPermissionSettings: (AppPermission) -> Void

    public init(
        settings: AppSettings,
        permissionSummary: PermissionSummary,
        openSystemSettings: @escaping () -> Void,
        openPermissionSettings: @escaping (AppPermission) -> Void = { _ in }
    ) {
        self.settings = settings
        self.permissionSummary = permissionSummary
        self.openSystemSettings = openSystemSettings
        self.openPermissionSettings = openPermissionSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    SettingsSection(title: "快捷键", iconName: "keyboard") {
                        SettingsRow(title: "设置页", value: settings.mainPanelShortcut.displayValue)
                        SettingsRow(title: "剪贴板", value: settings.clipboardShortcut.displayValue)
                        SettingsRow(title: "工具 2", value: settings.reservedTool2Shortcut.displayValue)
                        SettingsRow(title: "工具 3", value: settings.reservedTool3Shortcut.displayValue)
                    }

                    SettingsSection(title: "剪贴板", iconName: "doc.on.clipboard") {
                        StatusRow(title: "记录状态", isEnabled: settings.clipboard.isRecordingEnabled)
                        SettingsRow(
                            title: "历史上限",
                            value: "\(settings.clipboard.maxHistoryCount) 条"
                        )
                        SettingsRow(
                            title: "缓存上限",
                            value: "\(settings.clipboard.maxCacheMegabytes) MB"
                        )
                    }

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
                            title: "超级右键",
                            isEnabled: permissionSummary.canUseSuperRightClick,
                            permission: .accessibility,
                            openPermissionSettings: openPermissionSettings
                        )
                    }

                    SettingsSection(title: "系统", iconName: "gearshape") {
                        Button(action: openSystemSettings) {
                            Label("打开系统设置", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(22)
        }
        .liquidGlassPanel(cornerRadius: 30)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(
            minWidth: 560,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: 620,
            maxHeight: .infinity
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .liquidGlassModule(cornerRadius: 14, isSelected: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text("快捷键、剪贴板和权限")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
            }

            Spacer()
        }
        .padding(14)
        .liquidGlassModule(cornerRadius: 24)
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
                    .foregroundStyle(Color.white.opacity(0.70))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
            }

            VStack(spacing: 0) {
                content
            }
            .liquidGlassModule(cornerRadius: 22)
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.66))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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
                        .foregroundStyle(.white)

                    Spacer()

                    HStack(spacing: 6) {
                        Text("去授权")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.cyan.opacity(0.86))
                    .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
