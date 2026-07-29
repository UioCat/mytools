// 设置页面共用的分区、行布局和外观编辑器。
// 统一设置页结构，不持有跨页面业务状态。

import AppKit
import SwiftUI

/// 封装 `AppearanceSettingsEditor` 在 SwiftUI 展示层中的值语义和相关操作。
struct AppearanceSettingsEditor: View {
    let currentMode: AppAppearanceMode
    @Binding var selectedMode: AppAppearanceMode
    @Binding var saveMessage: String?
    let saveAppearanceMode: (AppAppearanceMode) throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("外观")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Spacer(minLength: 10)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Picker("外观", selection: selectionBinding) {
                ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel(Text("外观模式"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .onChange(of: currentMode) { _, mode in
            selectedMode = mode
        }
    }

    private var selectionBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { selectedMode },
            set: { mode in
                selectedMode = mode
                do {
                    try saveAppearanceMode(mode)
                    saveMessage = "已保存"
                } catch {
                    selectedMode = currentMode
                    saveMessage = "保存失败"
                }
            }
        )
    }
}
/// 封装 `SettingsSection` 在 SwiftUI 展示层中的值语义和相关操作。
struct SettingsSection<Content: View>: View {
    let title: String
    let iconName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)

                Text(title)
                    .font(.system(
                        size: MacToolsControlMetrics.sectionTitleFontSize,
                        weight: .semibold
                    ))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .liquidGlassGroup(spacing: 8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// 封装 `SettingsRow` 在 SwiftUI 展示层中的值语义和相关操作。
struct SettingsRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
