// 超级右键面板的预览、翻译和操作按钮视图。
// 根据展示模型渲染内容并转发动作，不执行文件或窗口操作。

import SwiftUI

/// 封装 `ContextActionView` 在 SwiftUI 展示层中的值语义和相关操作。
public struct ContextActionView: View {
    public let content: SuperPanelContent
    private let speechState: TranslationSpeechState
    private let performSpeech: (TranslationSpeechRequest) -> Void
    private let performAction: (SuperPanelActionID) -> Void

    /// 创建 `ContextActionView`，保存传入依赖并建立初始状态。
    public init(
        content: SuperPanelContent,
        speechState: TranslationSpeechState = .idle,
        performSpeech: @escaping (TranslationSpeechRequest) -> Void = { _ in },
        performAction: @escaping (SuperPanelActionID) -> Void
    ) {
        self.content = content
        self.speechState = speechState
        self.performSpeech = performSpeech
        self.performAction = performAction
    }

    public var body: some View {
        let panelSize = SuperPanelLayout.panelSize(for: content)

        VStack(spacing: 0) {
            header

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            scrollableBody
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .liquidGlassPanel(cornerRadius: LiquidGlassCornerGeometry.compactPanelRadius)
        .liquidGlassGroup(spacing: 12)
    }

    private var header: some View {
        HStack(spacing: SuperPanelLayout.headerSpacing) {
            Image(systemName: content.headerSystemImage)
                .font(.system(size: SuperPanelLayout.headerIconFontSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(
                    width: SuperPanelLayout.headerIconSize,
                    height: SuperPanelLayout.headerIconSize
                )

            VStack(alignment: .leading, spacing: SuperPanelLayout.headerTextSpacing) {
                Text(content.headerTitle)
                    .font(.system(size: SuperPanelLayout.headerTitleFontSize, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(content.headerSubtitle)
                    .font(.system(size: SuperPanelLayout.headerSubtitleFontSize, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            trailingHeaderAccessory
        }
        .padding(.horizontal, SuperPanelLayout.headerHorizontalPadding)
        .padding(.top, SuperPanelLayout.headerTopPadding)
        .padding(.bottom, SuperPanelLayout.headerBottomPadding)
    }

    private var previewSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(content.previewRows.enumerated()), id: \.offset) { index, row in
                previewRow(row)

                if index < content.previewRows.count - 1 {
                    Divider()
                        .padding(.leading, 68)
                        .opacity(0.35)
                }
            }
        }
        .padding(.vertical, usesTextLayout ? 8 : 6)
    }

    private var scrollableBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !content.previewRows.isEmpty {
                    previewSection

                    Divider()
                        .overlay(MacToolsGlassTheme.divider)
                        .opacity(usesTextLayout ? 0.9 : 0.55)
                }

                actionSection
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if content.kind == .text {
            translationActionSection
        } else {
            standardActionSection
        }
    }

    private var translationActionSection: some View {
        HStack(spacing: SuperPanelLayout.translationActionSpacing) {
            ForEach(primaryActions) { action in
                TranslationActionButton(action: action, performAction: performAction)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, SuperPanelLayout.translationActionSectionHorizontalPadding)
        .frame(height: SuperPanelLayout.translationActionSectionHeight)
    }

    private var standardActionSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(primaryActions.enumerated()), id: \.element.id) { index, action in
                SuperPanelActionRow(
                    action: action,
                    performAction: performAction
                )

                if index < primaryActions.count - 1 {
                    Divider()
                        .padding(.leading, 80)
                        .opacity(0.24)
                }
            }

            if !primaryActions.isEmpty, !windowLayoutActions.isEmpty {
                Divider()
                    .opacity(0.24)
            }

            if !windowLayoutActions.isEmpty {
                windowLayoutActionGrid
            }
        }
        .padding(.vertical, 8)
    }

    private var primaryActions: [SuperPanelActionDescriptor] {
        content.actions.filter { !$0.id.isWindowLayoutButton }
    }

    private var windowLayoutActions: [SuperPanelActionDescriptor] {
        content.actions.filter { $0.id.isWindowLayoutButton }
    }

    private var windowLayoutActionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                Text("窗口布局")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(windowLayoutActions) { action in
                    WindowLayoutActionButton(action: action, performAction: performAction)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    /// 展示预览字段的标签和值，并按内容类型限制文本行数。
    private func previewRow(_ row: SuperPanelPreviewRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(row.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacToolsGlassTheme.textTertiary)
                .frame(width: 48, alignment: .leading)

            Text(row.value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)
                .lineLimit(SuperPanelPreviewLineLimitPolicy.lineLimit(for: content.kind, row: row))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if let speechRequest = row.speechRequest {
                speechButton(for: speechRequest, textRole: row.label)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
    }

    /// 构建并返回 `speechButton` 对应的 SwiftUI 界面内容或展示状态。
    private func speechButton(
        for request: TranslationSpeechRequest,
        textRole: String
    ) -> some View {
        let isSpeaking = speechState.isSpeaking(request)
        let title = isSpeaking ? "停止朗读\(textRole)" : "朗读\(textRole)"

        return Button {
            performSpeech(request)
        } label: {
            Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(
                    width: MacToolsControlMetrics.inlineIconSize.width,
                    height: MacToolsControlMetrics.inlineIconSize.height
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSpeaking ? Color.white : MacToolsGlassTheme.textSecondary)
        .liquidGlassButtonStyle(
            cornerRadius: 10,
            isSelected: isSpeaking,
            minimumSize: MacToolsControlMetrics.inlineIconSize,
            showsIdleSurface: true
        )
        .accessibilityLabel(title)
        .help(title)
    }

    private var iconColor: Color {
        MacToolsGlassTheme.activeBlue
    }

    private var usesTextLayout: Bool {
        content.kind == .text || content.kind == .textTransit
    }

    private var trailingHeaderIconName: String {
        switch content.kind {
        case .text:
            return "magnifyingglass"
        case .textTransit:
            return "pin"
        case .fileSystem, .windowLayout:
            return "sparkles"
        }
    }

    @ViewBuilder
    private var trailingHeaderAccessory: some View {
        if content.showsLoadingIndicator {
            ProgressView()
                .controlSize(.small)
                .frame(
                    width: SuperPanelLayout.headerAccessorySize,
                    height: SuperPanelLayout.headerAccessorySize
                )
        } else {
            Image(systemName: trailingHeaderIconName)
                .font(.system(
                    size: SuperPanelLayout.headerTrailingIconFontSize,
                    weight: .regular
                ))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
        }
    }

}

/// 封装 `TranslationActionButton` 在 SwiftUI 展示层中的值语义和相关操作。
private struct TranslationActionButton: View {
    let action: SuperPanelActionDescriptor
    let performAction: (SuperPanelActionID) -> Void

    @State private var isHovering = false

    @ViewBuilder
    var body: some View {
        if isPrimary {
            actionButton
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
                    )
                )
                .onHover { isHovering = $0 }
        } else {
            actionButton
                .buttonStyle(
                    TranslationSecondaryActionButtonStyle(isHovering: isHovering)
                )
                .onHover { isHovering = $0 }
        }
    }

    private var actionButton: some View {
        Button {
            performAction(action.id)
        } label: {
            Text(action.title)
                .font(.system(
                    size: SuperPanelLayout.translationActionTitleFontSize,
                    weight: .semibold
                ))
                .foregroundStyle(isPrimary ? Color.white : MacToolsGlassTheme.textPrimary)
                .lineLimit(1)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
                        style: .continuous
                    )
                )
        }
    }

    private var isPrimary: Bool {
        action.id == .copyTranslatedText
    }
}

/// 让次要翻译操作与普通行一致，仅在悬停时浮起中性表面。
private struct TranslationSecondaryActionButtonStyle: ButtonStyle {
    let isHovering: Bool

    /// 让悬停和按下共享中性浮起表面，同时保留完整圆角命中区域。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, SuperPanelLayout.translationActionButtonHorizontalPadding)
            .frame(height: SuperPanelLayout.translationActionButtonHeight)
            .liquidGlassButtonHitTarget(
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
            )
            .liquidGlassInteractionSurface(
                state: isHovering || configuration.isPressed ? .hovered : .idle,
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
            )
    }
}

/// 封装 `SuperPanelActionRow` 在 SwiftUI 展示层中的值语义和相关操作。
private struct SuperPanelActionRow: View {
    let action: SuperPanelActionDescriptor
    let performAction: (SuperPanelActionID) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            performAction(action.id)
        } label: {
            HStack(spacing: rowSpacing) {
                Image(systemName: action.systemImage)
                    .font(.system(size: iconFontSize, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.activeBlue)
                .frame(width: iconSize, height: iconSize)

                Text(action.title)
                    .font(.system(size: titleFontSize, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: rowHeight)
            .contentShape(Rectangle())
            .liquidGlassInteractionSurface(
                state: isHovering ? .hovered : .idle,
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rowHeight: CGFloat {
        SuperPanelLayout.standardPrimaryActionRowHeight
    }

    private var iconSize: CGFloat {
        34
    }

    private var iconFontSize: CGFloat {
        17
    }

    private var titleFontSize: CGFloat {
        15
    }

    private var rowSpacing: CGFloat {
        16
    }

    private var horizontalPadding: CGFloat {
        14
    }

    private var verticalPadding: CGFloat {
        11
    }

}

/// 封装 `WindowLayoutActionButton` 在 SwiftUI 展示层中的值语义和相关操作。
private struct WindowLayoutActionButton: View {
    let action: SuperPanelActionDescriptor
    let performAction: (SuperPanelActionID) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            performAction(action.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)

                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }
            .foregroundStyle(MacToolsGlassTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: MacToolsControlMetrics.windowLayoutButtonHeight)
            .liquidGlassInteractionSurface(
                state: isHovering ? .hovered : .idle,
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
