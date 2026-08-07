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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                appearanceLabel

                Spacer(minLength: 20)

                appearancePicker
                    .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: 10) {
                appearanceLabel
                appearancePicker
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .onChange(of: currentMode) { _, mode in
            selectedMode = mode
        }
    }

    private var appearanceLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("外观")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            HStack(spacing: 5) {
                Text("选择 MacTools 的显示模式")

                if let saveMessage {
                    Text("·")
                    Text(saveMessage)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MacToolsGlassTheme.textTertiary)
            .lineLimit(1)
        }
    }

    private var appearancePicker: some View {
        Picker("外观", selection: selectionBinding) {
            ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("外观模式"))
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

/// 描述设置区块内容的表面层级；通用页使用卡片，其余页面保留现有平面结构。
enum SettingsSectionPresentation: Sendable {
    case flat
    case groupedCard
}

/// 封装 `SettingsSection` 在 SwiftUI 展示层中的值语义和相关操作。
struct SettingsSection<Content: View>: View {
    let title: String
    let iconName: String
    let presentation: SettingsSectionPresentation
    let content: Content

    init(
        title: String,
        iconName: String,
        presentation: SettingsSectionPresentation = .flat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.iconName = iconName
        self.presentation = presentation
        self.content = content()
    }

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

            sectionContent
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch presentation {
        case .flat:
            stackedContent
                .liquidGlassGroup(spacing: 8)
        case .groupedCard:
            stackedContent
                .liquidGlassModule(
                    cornerRadius: LiquidGlassCornerGeometry.controlRadius
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: LiquidGlassCornerGeometry.controlRadius,
                        style: .continuous
                    )
                    .stroke(MacToolsGlassTheme.border.opacity(0.46), lineWidth: 0.75)
                }
                .liquidGlassGroup(spacing: 8)
        }
    }

    private var stackedContent: some View {
        VStack(spacing: 0) {
            content
        }
    }
}

/// 在设置卡片内部绘制与行内容对齐的轻量分隔线。
struct SettingsSectionDivider: View {
    var body: some View {
        Divider()
            .overlay(MacToolsGlassTheme.divider)
            .opacity(0.8)
            .padding(.leading, 16)
    }
}

/// 展示带说明文字和右侧动作提示的整行设置入口。
struct SettingsActionRow: View {
    let title: String
    let detail: String
    let actionTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textTertiary)
                }

                Spacer(minLength: 16)

                HStack(spacing: 5) {
                    Text(actionTitle)
                    Image(systemName: systemImage)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(MacToolsGlassTheme.fieldFill, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(MacToolsGlassTheme.border.opacity(0.72), lineWidth: 0.75)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(
                maxWidth: .infinity,
                minHeight: MacToolsControlMetrics.settingsRowButtonMinimumHeight,
                alignment: .leading
            )
            .contentShape(RoundedRectangle(
                cornerRadius: LiquidGlassCornerGeometry.controlRadius,
                style: .continuous
            ))
        }
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.controlRadius,
            showsIdleSurface: false
        )
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
