// `SettingsNavigation` 的 SwiftUI 展示层实现。
// 负责设置分类定义和顶部导航，不直接拥有设置数据或持久化生命周期。

import SwiftUI

/// 描述设置页顶部导航中的分类。
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case clipboard
    case translation
    case automation
    case sync

    public var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .clipboard:
            return "剪贴板"
        case .translation:
            return "翻译"
        case .automation:
            return "自动化"
        case .sync:
            return "数据同步"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .clipboard:
            return "doc.on.clipboard"
        case .translation:
            return "character.book.closed"
        case .automation:
            return "wand.and.rays"
        case .sync:
            return "icloud"
        }
    }

    var sections: [SettingsSectionDestination] {
        switch self {
        case .general:
            return [.system, .shortcuts]
        case .clipboard:
            return [.clipboard]
        case .translation:
            return [.translation]
        case .automation:
            return [.superRightClick, .windowLayout, .permissions]
        case .sync:
            return [.sync]
        }
    }
}

enum SettingsPaneNavigationDirection {
    case previous
    case next
}

enum SettingsPaneNavigator {
    static func pane(
        adjacentTo currentPane: SettingsPane,
        direction: SettingsPaneNavigationDirection
    ) -> SettingsPane {
        let panes = SettingsPane.allCases
        guard let currentIndex = panes.firstIndex(of: currentPane), !panes.isEmpty else {
            return currentPane
        }

        let offset = direction == .previous ? panes.count - 1 : 1
        return panes[(currentIndex + offset) % panes.count]
    }
}

/// 描述每个设置分类中展示的内容区块。
enum SettingsSectionDestination: String, Identifiable, Sendable {
    case system
    case shortcuts
    case clipboard
    case translation
    case superRightClick
    case windowLayout
    case permissions
    case sync

    var id: Self { self }
}

/// 设置页顶部分类工具栏。
struct SettingsPaneToolbar: View {
    private struct FocusTarget: Hashable {
        let pane: SettingsPane
        let compact: Bool
    }

    @Binding var selection: SettingsPane
    @FocusState private var focusTarget: FocusTarget?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbar(compact: false)
            toolbar(compact: true)
        }
        .padding(8)
        .liquidGlassModule(cornerRadius: 20)
        .liquidGlassGroup(spacing: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("设置分类"))
    }

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(SettingsPane.allCases) { pane in
                navigationButton(for: pane, compact: compact)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func navigationButton(for pane: SettingsPane, compact: Bool) -> some View {
        let isSelected = selection == pane
        let minimumWidth: CGFloat = compact ? 48 : 80
        let buttonFocusTarget = FocusTarget(pane: pane, compact: compact)

        return Button {
            selection = pane
            focusTarget = buttonFocusTarget
        } label: {
            VStack(spacing: compact ? 0 : 5) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 15, weight: .semibold))

                if !compact {
                    Text(pane.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(isSelected ? MacToolsGlassTheme.selectionBlue : MacToolsGlassTheme.textSecondary)
        .liquidGlassButtonStyle(
            cornerRadius: 14,
            isSelected: isSelected,
            minimumSize: CGSize(width: minimumWidth, height: 48),
            showsIdleSurface: false
        )
        .accessibilityLabel(Text(pane.title))
        .accessibilityValue(Text(isSelected ? "已选择" : ""))
        .help(pane.title)
        .focusable()
        .focused($focusTarget, equals: buttonFocusTarget)
        .onKeyPress(.leftArrow) {
            moveSelection(from: pane, compact: compact, direction: .previous)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(from: pane, compact: compact, direction: .next)
            return .handled
        }
    }

    private func moveSelection(
        from pane: SettingsPane,
        compact: Bool,
        direction: SettingsPaneNavigationDirection
    ) {
        let destination = SettingsPaneNavigator.pane(adjacentTo: pane, direction: direction)
        selection = destination
        focusTarget = FocusTarget(pane: destination, compact: compact)
    }
}
