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
            updateSummaryRow

            SettingsSectionDivider()

            updateToggleRow(
                title: "自动检查更新",
                detail: "每天检查一次稳定版本",
                isOn: Binding(
                    get: { state.automaticallyChecksForUpdates },
                    set: setAutomaticallyChecksForUpdates
                )
            )

            SettingsSectionDivider()

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

    private var updateSummaryRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("MacTools \(state.version)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Text("构建 \(state.buildNumber) · 当前已安装版本")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }

            Spacer(minLength: 16)

            Button(action: checkForUpdates) {
                HStack(spacing: 6) {
                    if !state.canCheckForUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text("检查更新…")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(RoundedRectangle(
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
                    style: .continuous
                ))
            }
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
            .liquidGlassButtonStyle(
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
                minimumSize: CGSize(width: 112, height: 34)
            )
            .disabled(!state.canCheckForUpdates)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
    }
}
