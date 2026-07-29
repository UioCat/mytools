// 剪贴板记录和超级右键配置编辑器。
// 维护未保存草稿并提交完整设置值，不直接更新运行时服务。

import AppKit
import SwiftUI

/// 封装 `ClipboardSettingsEditor` 在 SwiftUI 展示层中的值语义和相关操作。
struct ClipboardSettingsEditor: View {
    let currentSettings: ClipboardSettings
    let defaultCacheDirectory: URL
    let openStorageFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            StatusRow(title: "记录状态", isEnabled: currentSettings.isRecordingEnabled, enabledTitle: "已启用", disabledTitle: "未启用")
            SettingsRow(title: "历史上限", value: "\(currentSettings.maxHistoryCount) 条")

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("统一存储")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Text(cacheStorageDisplay)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(cacheStorageDisplay)
                }

                Spacer(minLength: 10)
                HStack(spacing: 6) {
                    Text("由 MacTools 管理")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textSecondary)

                    Button {
                        FolderOpenInteraction.openClipboardStorage(openFolder: openStorageFolder)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(
                                width: MacToolsControlMetrics.inlineIconSize.width,
                                height: MacToolsControlMetrics.inlineIconSize.height
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .help("打开统一存储文件夹")
                    .accessibilityLabel(Text("打开统一存储文件夹"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            SettingsRow(title: "图片对象", value: "按内容去重 · 自动回收")
        }
    }

    private var cacheStorageDisplay: String {
        ClipboardCacheStorageDisplay.displayPath(
            configuredPath: "",
            defaultDirectory: defaultCacheDirectory
        )
    }
}
/// 封装 `SuperRightClickSettingsEditor` 在 SwiftUI 展示层中的值语义和相关操作。
struct SuperRightClickSettingsEditor: View {
    let currentSettings: SuperRightClickSettings
    @Binding var longPressMilliseconds: Double
    @Binding var saveMessage: String?
    let saveSuperRightClickSettings: (SuperRightClickSettings) throws -> Void
    @State private var isEditingLongPressMilliseconds = false
    @State private var isCommittingLongPressMilliseconds = false

    private var normalizedMilliseconds: Int {
        SuperRightClickResponseSpeed.committedMilliseconds(forSliderValue: longPressMilliseconds)
    }

    private var sliderRange: ClosedRange<Double> {
        let lowerBound = Double(SuperRightClickResponseSpeed.minimumMilliseconds)
        let upperBound = Double(SuperRightClickResponseSpeed.maximumMilliseconds)
        return lowerBound...upperBound
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusRow(title: "状态", isEnabled: currentSettings.isEnabled, enabledTitle: "已启用", disabledTitle: "未启用")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("长按毫秒响应")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textPrimary)

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(spacing: 8) {
                        Slider(
                            value: $longPressMilliseconds,
                            in: sliderRange,
                            onEditingChanged: handleSliderEditingChanged(_:)
                        )
                        .tint(MacToolsGlassTheme.activeBlue)
                        .frame(maxWidth: 260)
                        .accessibilityLabel(Text("长按毫秒响应"))
                        .accessibilityValue(Text(SuperRightClickResponseSpeed.displayValue(for: normalizedMilliseconds)))

                        HStack {
                            ForEach(SuperRightClickResponseSpeed.markerMilliseconds, id: \.self) { milliseconds in
                                Text(SuperRightClickResponseSpeed.displayValue(for: milliseconds))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                                if milliseconds != SuperRightClickResponseSpeed.maximumMilliseconds {
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .frame(maxWidth: 260)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .onChange(of: longPressMilliseconds) {
            guard !isCommittingLongPressMilliseconds else {
                isCommittingLongPressMilliseconds = false
                return
            }

            if !isEditingLongPressMilliseconds {
                commitSliderValue()
            }
        }
    }

    /// 记录滑块是否仍在拖动，并在拖动结束时统一持久化归一化后的长按阈值。
    private func handleSliderEditingChanged(_ isEditing: Bool) {
        isEditingLongPressMilliseconds = isEditing
        if !isEditing {
            commitSliderValue()
        }
    }

    /// 将滑块值吸附到支持的毫秒档位后保存，避免编辑过程中重复写入设置。
    private func commitSliderValue() {
        let milliseconds = normalizedMilliseconds
        if Int(longPressMilliseconds) != milliseconds {
            isCommittingLongPressMilliseconds = true
            longPressMilliseconds = Double(milliseconds)
        }

        do {
            try saveSuperRightClickSettings(
                SuperRightClickSettings(
                    isEnabled: currentSettings.isEnabled,
                    longPressMilliseconds: milliseconds
                )
            )
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }
}
