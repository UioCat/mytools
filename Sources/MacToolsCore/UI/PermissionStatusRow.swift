// `PermissionStatusRow` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import AppKit
import SwiftUI

/// 封装 `StatusRow` 在 SwiftUI 展示层中的值语义和相关操作。
struct StatusRow: View {
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

/// 封装 `PermissionStatusRow` 在 SwiftUI 展示层中的值语义和相关操作。
struct PermissionStatusRow: View {
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
