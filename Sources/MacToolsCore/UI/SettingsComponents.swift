import AppKit
import SwiftUI

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
struct SettingsSection<Content: View>: View {
    let title: String
    let iconName: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }

            VStack(spacing: 0) {
                content
            }
            .liquidGlassModule(cornerRadius: 22)
            .liquidGlassGroup(spacing: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

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
