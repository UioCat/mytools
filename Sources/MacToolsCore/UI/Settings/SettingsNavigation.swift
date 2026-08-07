// 设置分类定义、键盘选择规则和顶部导航。
// 只维护当前分类选择，不拥有设置数据或持久化生命周期。

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
            return [.system, .softwareUpdate, .shortcuts]
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

/// 描述设置分类的循环导航方向。
enum SettingsPaneNavigationDirection {
    case previous
    case next
}

/// 根据固定分类顺序计算键盘导航目标。
enum SettingsPaneNavigator {
    /// 按固定分类顺序循环选择相邻页面，首尾之间保持键盘导航连续。
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
    case softwareUpdate
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
    /// 将分类和紧凑形态组合为唯一焦点身份，避免 ViewThatFits 两套按钮共享焦点。
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
        .liquidGlassGroup(spacing: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("设置分类"))
    }

    /// 根据可用宽度构建完整标题或紧凑图标工具栏。
    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(SettingsPane.allCases) { pane in
                navigationButton(for: pane, compact: compact)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 构建设置分类按钮，并保持鼠标选择、辅助功能与键盘焦点使用同一状态。
    private func navigationButton(for pane: SettingsPane, compact: Bool) -> some View {
        let isSelected = selection == pane
        let minimumWidth: CGFloat = compact ? 48 : 80
        let buttonFocusTarget = FocusTarget(pane: pane, compact: compact)

        return Button {
            selection = pane
            focusTarget = buttonFocusTarget
        } label: {
            HStack(spacing: compact ? 0 : 6) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: 13, weight: .semibold))

                if !compact {
                    Text(pane.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: MacToolsControlMetrics.settingsCategoryHeight)
            .contentShape(RoundedRectangle(
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
                style: .continuous
            ))
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? MacToolsGlassTheme.selectionBlue : Color.clear)
                    .frame(width: 18, height: 3)
                    .padding(.bottom, 2)
            }
        }
        .foregroundStyle(isSelected ? MacToolsGlassTheme.selectionBlue : MacToolsGlassTheme.textSecondary)
        .liquidGlassButtonStyle(
            cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
            isSelected: isSelected,
            minimumSize: CGSize(
                width: minimumWidth,
                height: MacToolsControlMetrics.settingsCategoryHeight
            ),
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

    /// 循环移动分类选择，并把焦点同步到当前工具栏形态中的目标按钮。
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
