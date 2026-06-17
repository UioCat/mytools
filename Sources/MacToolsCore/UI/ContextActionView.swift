import SwiftUI

public struct ContextActionView: View {
    public let content: SuperPanelContent
    private let performAction: (SuperPanelActionID) -> Void

    public init(
        content: SuperPanelContent,
        performAction: @escaping (SuperPanelActionID) -> Void
    ) {
        self.content = content
        self.performAction = performAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            scrollingPreviewSection

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(usesTextLayout ? 0.9 : 0.55)

            actionSection
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(panelBackground)
        .clipShape(panelShape)
        .overlay(panelBorder)
        .environment(\.colorScheme, .light)
        .shadow(color: .black.opacity(0.38), radius: 34, x: 0, y: 20)
        .shadow(color: MacToolsGlassTheme.activeBlue.opacity(0.10), radius: 28, x: 0, y: 12)
    }

    private var panelWidth: CGFloat {
        usesTextLayout ? 500 : 520
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(iconColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(iconColor.opacity(0.42), lineWidth: 1)
                    )
                    .shadow(color: iconColor.opacity(0.20), radius: 10, x: 0, y: 5)

                Image(systemName: content.headerSystemImage)
                    .font(.system(size: usesTextLayout ? 22 : 24, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(content.headerTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)

                Text(content.headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            trailingHeaderAccessory
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(headerBackground)
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
        .background(MacToolsGlassTheme.fieldFill.opacity(usesTextLayout ? 1 : 0))
    }

    private var scrollingPreviewSection: some View {
        ScrollView {
            previewSection
        }
        .frame(maxHeight: usesTextLayout ? 380 : nil)
    }

    private var actionSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(primaryActions.enumerated()), id: \.element.id) { index, action in
                SuperPanelActionRow(action: action, performAction: performAction)

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
        .background(Color.white.opacity(content.kind == .fileSystem ? 0.018 : 0.0))
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

    private func previewRow(_ row: SuperPanelPreviewRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
    }

    private var panelBackground: some View {
        ZStack {
            panelShape
                .fill(.ultraThinMaterial)

            panelShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.105),
                            MacToolsGlassTheme.panelTint.opacity(0.145),
                            Color.white.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            panelShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.clear,
                            MacToolsGlassTheme.activeBlue.opacity(0.055)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
        }
    }

    private var headerBackground: some View {
        ZStack {
            if content.kind == .fileSystem {
                LinearGradient(
                    colors: [
                        MacToolsGlassTheme.activeBlue.opacity(0.085),
                        Color.white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.white.opacity(0.030)
            }
        }
    }

    private var panelBorder: some View {
        ZStack {
            panelShape
                .strokeBorder(Color.white.opacity(0.46), lineWidth: 1.1)

            panelShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.46),
                            MacToolsGlassTheme.activeBlue.opacity(0.16),
                            Color.black.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .blendMode(.overlay)
        }
    }

    private var iconColor: Color {
        switch content.kind {
        case .text:
            return MacToolsGlassTheme.activeBlue
        case .textTransit:
            return Color.purple.opacity(0.92)
        case .fileSystem, .windowLayout:
            return MacToolsGlassTheme.activeBlue
        }
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
                .controlSize(.regular)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: trailingHeaderIconName)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
        }
    }

}

private struct SuperPanelActionRow: View {
    let action: SuperPanelActionDescriptor
    let performAction: (SuperPanelActionID) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            performAction(action.id)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)

                    Image(systemName: action.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconForeground)
                }
                .frame(width: 34, height: 34)

                Text(action.title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(isHovering ? MacToolsGlassTheme.rowHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var iconBackground: Color {
        switch action.id {
        case .copyTranslatedText, .copyTransitText, .copyPath, .createNewFile:
            return MacToolsGlassTheme.activeBlue
        case .textTransit:
            return Color.purple
        case .openTerminal:
            return Color.white.opacity(0.14)
        case .revealInFinder:
            return Color.indigo
        case .openClaudeCode, .openClaudeCodeSkipConfirmation:
            return Color.orange.opacity(0.76)
        case .windowLayoutButton:
            return MacToolsGlassTheme.success.opacity(0.78)
        }
    }

    private var iconForeground: Color {
        switch action.id {
        case .openTerminal:
            return MacToolsGlassTheme.textPrimary
        default:
            return .white
        }
    }
}

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
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? MacToolsGlassTheme.activeBlue.opacity(0.16) : Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isHovering ? MacToolsGlassTheme.activeBlue.opacity(0.45) : MacToolsGlassTheme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
