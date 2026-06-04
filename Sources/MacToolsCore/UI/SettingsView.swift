import SwiftUI

public struct SettingsView: View {
    public let settings: AppSettings
    public let permissionSummary: PermissionSummary
    public let openSystemSettings: () -> Void

    public init(
        settings: AppSettings,
        permissionSummary: PermissionSummary,
        openSystemSettings: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissionSummary = permissionSummary
        self.openSystemSettings = openSystemSettings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("设置")
                    .font(.system(size: 22, weight: .semibold))

                SettingsSection(title: "快捷键") {
                    SettingsRow(title: "主面板", value: settings.mainPanelShortcut.displayValue)
                    SettingsRow(title: "剪贴板", value: settings.clipboardShortcut.displayValue)
                    SettingsRow(title: "工具 2", value: settings.reservedTool2Shortcut.displayValue)
                    SettingsRow(title: "工具 3", value: settings.reservedTool3Shortcut.displayValue)
                }

                SettingsSection(title: "剪贴板") {
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

                SettingsSection(title: "权限") {
                    StatusRow(title: "辅助功能", isEnabled: permissionSummary.hasAccessibility)
                    StatusRow(title: "输入监控", isEnabled: permissionSummary.hasInputMonitoring)
                    StatusRow(
                        title: "超级右键",
                        isEnabled: permissionSummary.canUseSuperRightClick
                    )

                    Button(action: openSystemSettings) {
                        Label("打开系统设置", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .frame(width: 560, height: 520)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct StatusRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        SettingsRow(title: title, value: isEnabled ? "已允许" : "未授权")
    }
}
