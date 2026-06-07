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
                .opacity(0.55)

            scrollingPreviewSection

            Divider()
                .opacity(usesTextLayout ? 0.55 : 0.25)

            actionSection
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(panelBackground)
        .clipShape(panelShape)
        .overlay(panelBorder)
        .shadow(color: .black.opacity(0.24), radius: 30, x: 0, y: 18)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
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
                    .fill(Color.white.opacity(usesTextLayout ? 0.90 : 0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

                Image(systemName: content.headerSystemImage)
                    .font(.system(size: usesTextLayout ? 22 : 24, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(content.headerTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Text(content.headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Image(systemName: trailingHeaderIconName)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(0.86))
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
        .background(Color.black.opacity(usesTextLayout ? 0.035 : 0.0))
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
        .background(Color.white.opacity(content.kind == .fileSystem ? 0.58 : 0.0))
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
                    .foregroundStyle(Color.black.opacity(0.56))

                Text("窗口布局")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.56))
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
                .foregroundStyle(Color.secondary)
                .frame(width: 48, alignment: .leading)

            Text(row.value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.88))
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
                .fill(.regularMaterial)

            panelShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(usesTextLayout ? 0.90 : 0.66),
                            Color.white.opacity(usesTextLayout ? 0.84 : 0.50)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private var headerBackground: some View {
        ZStack {
            if content.kind == .fileSystem {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.white.opacity(0.18)
            }
        }
    }

    private var panelBorder: some View {
        ZStack {
            panelShape
                .strokeBorder(Color.white.opacity(0.76), lineWidth: 1.1)

            panelShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.18)
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
            return Color.gray.opacity(0.88)
        case .textTransit:
            return Color.purple.opacity(0.88)
        case .fileSystem:
            return Color.accentColor
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
        case .fileSystem:
            return "sparkles"
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
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 0)
                    .fill(isHovering ? Color.black.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var iconBackground: Color {
        switch action.id {
        case .copyTranslatedText, .copyTransitText, .copyPath, .createNewFile:
            return Color.blue
        case .textTransit:
            return Color.purple
        case .openTerminal:
            return Color.black.opacity(0.86)
        case .revealInFinder:
            return Color.indigo
        case .openClaudeCode, .openClaudeCodeSkipConfirmation:
            return Color.orange.opacity(0.86)
        case .windowLayoutButton:
            return Color.green.opacity(0.82)
        }
    }

    private var iconForeground: Color {
        switch action.id {
        case .openTerminal:
            return Color.white.opacity(0.92)
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
            .foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.black.opacity(0.10) : Color.white.opacity(0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.70), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
