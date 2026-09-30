// 登录时自动启动的展示状态与设置控件。
// 只表达用户意图，不直接依赖 ServiceManagement 或持久化系统状态。

import SwiftUI

/// 系统登录项服务向通用设置页面提供的只读状态。
public enum LaunchAtLoginSettingsState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case registrationMissing
    case requiresAppBundle
    case unavailable
    case failed(isEnabled: Bool, message: String)

    public var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .failed(let isEnabled, _):
            return isEnabled
        case .disabled, .registrationMissing, .requiresAppBundle, .unavailable:
            return false
        }
    }

    public var isAvailable: Bool {
        self != .unavailable && self != .requiresAppBundle
    }

    var detailText: String {
        switch self {
        case .disabled:
            return "登录 Mac 后自动运行 MacTools"
        case .enabled:
            return "已由 macOS 登录项管理"
        case .requiresApproval:
            return "需要在系统设置的登录项中允许"
        case .registrationMissing:
            return "开启后将向 macOS 注册登录项"
        case .requiresAppBundle:
            return "请打开完整的 MacTools.app 后设置"
        case .unavailable:
            return "无法读取登录项状态，请在系统设置中检查"
        case .failed(_, let message):
            return message
        }
    }

    var requiresSystemApproval: Bool {
        self == .requiresApproval
    }

    var showsSystemSettingsAction: Bool {
        switch self {
        case .requiresApproval, .failed, .unavailable:
            return true
        case .disabled, .enabled, .registrationMissing, .requiresAppBundle:
            return false
        }
    }
}

/// 在通用设置中展示登录时自动启动开关和系统批准入口。
struct LaunchAtLoginSettingsEditor: View {
    let state: LaunchAtLoginSettingsState
    let setEnabled: (Bool) -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toggleRow

            if state.showsSystemSettingsAction {
                SettingsSectionDivider()

                SettingsActionRow(
                    title: state.requiresSystemApproval ? "允许自动启动" : "检查登录项",
                    detail: state.requiresSystemApproval
                        ? "macOS 需要确认此登录项"
                        : "切换开关可重试，也可查看系统登录项",
                    actionTitle: "打开登录项",
                    systemImage: "arrow.up.forward",
                    action: openSystemSettings
                )
            }
        }
    }

    private var toggleRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("登录时自动启动")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Text(state.detailText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }

            Spacer(minLength: 10)

            Toggle(
                "登录时自动启动",
                isOn: Binding(get: { state.isEnabled }, set: setEnabled)
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(Text("登录时自动启动"))
            .accessibilityHint(Text(state.detailText))
            .disabled(!state.isAvailable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
    }
}
