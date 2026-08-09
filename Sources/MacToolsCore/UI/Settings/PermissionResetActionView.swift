// 权限迁移的一次性整理操作。
// 负责确认、结果提示与异步状态，不让设置组合根承载流程细节。

import SwiftUI

struct PermissionResetActionView: View {
    let resetPermissionDecisions: () async throws -> Void
    let openPermissionSettings: (AppPermission) -> Void
    @State private var alert: PermissionResetAlert?

    var body: some View {
        Group {
            SettingsSectionDivider()

            SettingsActionRow(
                title: "整理旧权限记录",
                detail: "签名更新后一次性清理 MacTools 的旧授权",
                actionTitle: "整理",
                systemImage: "arrow.counterclockwise",
                action: {
                    alert = .confirmation
                }
            )
        }
        .alert(item: $alert) { alert in
            systemAlert(for: alert)
        }
    }

    private func systemAlert(for alert: PermissionResetAlert) -> Alert {
        switch alert {
        case .confirmation:
            return Alert(
                title: Text("整理 MacTools 的旧权限记录？"),
                message: Text(
                    "这只会清理当前 MacTools 应用标识的辅助功能、输入监控、自动粘贴、屏幕与系统音频录制，以及访达自动化授权，不影响其他应用。"
                ),
                primaryButton: .destructive(Text("整理")) {
                    Task { @MainActor in
                        do {
                            try await resetPermissionDecisions()
                            self.alert = .success
                        } catch {
                            self.alert = .failure(error.localizedDescription)
                        }
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        case .success:
            return Alert(
                title: Text("旧权限记录已整理"),
                message: Text(
                    "请重新允许辅助功能、输入监控、自动粘贴，以及屏幕与系统音频录制；首次使用访达目录功能时重新允许访达自动化。完成后退出并重新打开 MacTools。"
                ),
                primaryButton: .default(Text("打开辅助功能设置")) {
                    openPermissionSettings(.accessibility)
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        case let .failure(message):
            return Alert(
                title: Text("无法整理权限记录"),
                message: Text(message),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

private enum PermissionResetAlert: Identifiable {
    case confirmation
    case success
    case failure(String)

    var id: String {
        switch self {
        case .confirmation:
            return "confirmation"
        case .success:
            return "success"
        case let .failure(message):
            return "failure-\(message)"
        }
    }
}
