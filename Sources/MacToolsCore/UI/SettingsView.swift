import AppKit
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
        ZStack {
            auroraGlassBackground

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
                            StatusRow(title: "辅助功能", isEnabled: permissionSummary.hasAccessibility)
                            StatusRow(title: "输入监控", isEnabled: permissionSummary.hasInputMonitoring)
                            StatusRow(
                                title: "超级右键",
                                isEnabled: permissionSummary.canUseSuperRightClick
                            )
                        }

                        SettingsSection(title: "系统", iconName: "gearshape") {
                            Button(action: openSystemSettings) {
                                Label("打开系统设置", systemImage: "arrow.up.forward.app")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .padding(22)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 18)
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
                .background(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.84), Color.indigo.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 22, weight: .semibold))
                Text("快捷键、剪贴板和权限")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var auroraGlassBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.26))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.15), Color.clear, Color.indigo.opacity(0.13)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
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
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                content
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.16),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), Color.cyan.opacity(0.16), Color.indigo.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
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
