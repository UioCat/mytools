// 软件更新的展示状态与设置控件。
// 只表达用户意图，不直接依赖 Sparkle 或执行网络和应用替换操作。

import SwiftUI

/// 软件更新服务向通用设置页面提供的只读快照。
public struct SoftwareUpdateSettingsState: Equatable, Sendable {
    public var version: String
    public var buildNumber: String
    public var canCheckForUpdates: Bool
    public var automaticallyChecksForUpdates: Bool
    public var automaticallyDownloadsUpdates: Bool

    public init(
        version: String,
        buildNumber: String,
        canCheckForUpdates: Bool,
        automaticallyChecksForUpdates: Bool,
        automaticallyDownloadsUpdates: Bool
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.canCheckForUpdates = canCheckForUpdates
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
    }

    public static let unavailable = SoftwareUpdateSettingsState(
        version: "—",
        buildNumber: "—",
        canCheckForUpdates: false,
        automaticallyChecksForUpdates: false,
        automaticallyDownloadsUpdates: false
    )

    public var versionDescription: String {
        "\(version)（构建 \(buildNumber)）"
    }
}

/// 在通用设置中展示版本、手动检查入口和 Sparkle 设备级偏好。
struct SoftwareUpdateSettingsEditor: View {
    let state: SoftwareUpdateSettingsState
    let checkForUpdates: () -> Void
    let setAutomaticallyChecksForUpdates: (Bool) -> Void
    let setAutomaticallyDownloadsUpdates: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "当前版本", value: state.versionDescription)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            Button(action: checkForUpdates) {
                HStack(spacing: 10) {
                    Label("检查更新…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .medium))

                    Spacer(minLength: 10)

                    if !state.canCheckForUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: MacToolsControlMetrics.settingsRowButtonMinimumHeight)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
            .liquidGlassButtonStyle(cornerRadius: 14, showsIdleSurface: false)
            .disabled(!state.canCheckForUpdates)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            updateToggleRow(
                title: "自动检查更新",
                detail: "每天检查一次稳定版本",
                isOn: Binding(
                    get: { state.automaticallyChecksForUpdates },
                    set: setAutomaticallyChecksForUpdates
                )
            )

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            updateToggleRow(
                title: "自动下载并安装更新",
                detail: "后台准备更新，并在应用退出时安装",
                isOn: Binding(
                    get: { state.automaticallyDownloadsUpdates },
                    set: setAutomaticallyDownloadsUpdates
                )
            )
            .disabled(!state.automaticallyChecksForUpdates)
        }
    }

    private func updateToggleRow(
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }

            Spacer(minLength: 10)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(title))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: MacToolsControlMetrics.settingsRowButtonMinimumHeight)
    }
}
