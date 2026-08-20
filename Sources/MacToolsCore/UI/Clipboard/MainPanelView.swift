// 剪贴板主面板的搜索、分类和结果列表组合视图。
// 负责展示状态与用户意图转发，不拥有仓储或粘贴服务。

import AppKit
import SwiftUI

/// 描述 `ClipboardSelectionAction` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum ClipboardSelectionAction {
    case copy
    case copyAndPaste
}

/// 描述 `ClipboardPanelMode` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum ClipboardPanelMode: CaseIterable {
    case all
    case text
    case images
    case favorites

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .text:
            return "文本"
        case .images:
            return "图像"
        case .favorites:
            return "收藏"
        }
    }

    var iconName: String {
        switch self {
        case .all:
            return "doc.on.clipboard"
        case .text:
            return "text.justify.leading"
        case .images:
            return "photo"
        case .favorites:
            return "star.fill"
        }
    }
}

/// 描述 `ClipboardPanelModeNavigationDirection` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum ClipboardPanelModeNavigationDirection: Equatable {
    case previous
    case next
}

/// 描述 `ClipboardPanelModeNavigator` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum ClipboardPanelModeNavigator {
    /// 构建并返回 `direction` 对应的 SwiftUI 界面内容或展示状态。
    static func direction(forKeyCode keyCode: UInt16) -> ClipboardPanelModeNavigationDirection? {
        switch keyCode {
        case 123:
            return .previous
        case 124:
            return .next
        default:
            return nil
        }
    }

    /// 构建并返回 `mode` 对应的 SwiftUI 界面内容或展示状态。
    static func mode(
        adjacentTo currentMode: ClipboardPanelMode,
        direction: ClipboardPanelModeNavigationDirection
    ) -> ClipboardPanelMode {
        let modes = ClipboardPanelMode.allCases
        guard let currentIndex = modes.firstIndex(of: currentMode) else {
            return currentMode
        }

        let offset = direction == .previous ? modes.count - 1 : 1
        let nextIndex = (currentIndex + offset) % modes.count
        return modes[nextIndex]
    }
}

/// 封装 `ClipboardPanelItemSummary` 在 SwiftUI 展示层中的值语义和相关操作。
struct ClipboardTagCount: Equatable, Identifiable {
    let name: String
    let count: Int

    var id: String { ClipboardTagPolicy.comparisonKey(for: name) }
}

/// 汇总收藏数量、可清理状态和收藏标签计数。
struct ClipboardPanelItemSummary: Equatable {
    let favoriteCount: Int
    let hasClearableItems: Bool
    let tagCounts: [ClipboardTagCount]

    /// 创建 `ClipboardPanelItemSummary`，保存传入依赖并建立初始状态。
    init(items: [ClipboardItem]) {
        var favoriteCount = 0
        var hasClearableItems = false
        var tagNamesByKey: [String: String] = [:]
        var countsByKey: [String: Int] = [:]

        for item in items {
            if item.isFavorite {
                favoriteCount += 1
                for tag in item.tags {
                    let key = ClipboardTagPolicy.comparisonKey(for: tag)
                    tagNamesByKey[key] = tagNamesByKey[key] ?? tag
                    countsByKey[key, default: 0] += 1
                }
            } else {
                hasClearableItems = true
            }
        }

        self.favoriteCount = favoriteCount
        self.hasClearableItems = hasClearableItems
        self.tagCounts = tagNamesByKey
            .map { key, name in
                ClipboardTagCount(name: name, count: countsByKey[key, default: 0])
            }
            .sorted {
                ClipboardTagPolicy.comparisonKey(for: $0.name)
                    < ClipboardTagPolicy.comparisonKey(for: $1.name)
            }
    }

    /// 判断当前收藏记录是否仍使用指定标签。
    func containsTag(_ tag: String) -> Bool {
        let key = ClipboardTagPolicy.comparisonKey(for: tag)
        return tagCounts.contains { $0.id == key }
    }
}

/// 封装 `ClipboardPanelRenderState` 在 SwiftUI 展示层中的值语义和相关操作。
struct ClipboardPanelRenderState {
    let itemSummary: ClipboardPanelItemSummary
    let filteredItems: [ClipboardItem]
    let selectedItem: ClipboardItem?

    /// 创建 `ClipboardPanelRenderState`，保存传入依赖并建立初始状态。
    init(
        items: [ClipboardItem],
        mode: ClipboardPanelMode,
        query: String,
        selectedTag: String? = nil,
        selectedItemID: ClipboardItem.ID?
    ) {
        self.itemSummary = ClipboardPanelItemSummary(items: items)
        self.filteredItems = Self.filteredItems(
            items: items,
            mode: mode,
            query: query,
            selectedTag: selectedTag
        )
        self.selectedItem = Self.selectedItem(in: filteredItems, selectedItemID: selectedItemID)
    }

    /// 构建并返回 `filteredItems` 对应的 SwiftUI 界面内容或展示状态。
    static func filteredItems(
        items: [ClipboardItem],
        mode: ClipboardPanelMode,
        query: String,
        selectedTag: String? = nil
    ) -> [ClipboardItem] {
        let modeItems: [ClipboardItem]
        switch mode {
        case .all:
            modeItems = items
        case .text:
            modeItems = items.filter { $0.kind == .text || $0.kind == .url }
        case .images:
            modeItems = items.filter { $0.kind == .imageData || $0.kind == .imageFile }
        case .favorites:
            modeItems = items.filter(\.isFavorite)
        }

        let tagFilteredItems: [ClipboardItem]
        if mode == .favorites, let selectedTag {
            tagFilteredItems = modeItems.filter {
                ClipboardTagPolicy.contains(selectedTag, in: $0.tags)
            }
        } else {
            tagFilteredItems = modeItems
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return tagFilteredItems
        }

        return tagFilteredItems.filter { item in
            item.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                || item.searchableText.localizedCaseInsensitiveContains(trimmedQuery)
                || (mode == .favorites && item.tags.contains {
                    $0.localizedCaseInsensitiveContains(trimmedQuery)
                })
        }
    }

    /// 解析并返回 `selectedItem` 对应的 SwiftUI 展示层结果。
    private static func selectedItem(
        in filteredItems: [ClipboardItem],
        selectedItemID: ClipboardItem.ID?
    ) -> ClipboardItem? {
        if let selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID }) {
            return item
        }

        return filteredItems.first
    }
}

/// 描述 `ClipboardItemClickAction` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum ClipboardItemClickAction: Equatable {
    case select
    case paste
}

/// 描述 `ClipboardItemClickResolver` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum ClipboardItemClickResolver {
    /// 第一次点击选择条目，只有再次点击同一已武装条目时才执行粘贴。
    static func action(
        clickedItemID: ClipboardItem.ID,
        selectedItemID: ClipboardItem.ID?,
        armedItemID: ClipboardItem.ID?
    ) -> ClipboardItemClickAction {
        if clickedItemID == selectedItemID,
           clickedItemID == armedItemID {
            return .paste
        }

        return .select
    }
}

/// 封装 `MainPanelView` 在 SwiftUI 展示层中的值语义和相关操作。
public struct MainPanelView: View {
    @Environment(\.mainWorkspaceSidebarChrome) private var workspaceSidebarChrome
    @State private var query = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var armedMouseItemID: ClipboardItem.ID?
    @State private var mode: ClipboardPanelMode = .all
    @State private var selectedTag: String?
    @FocusState private var isSearchFocused: Bool

    public let items: [ClipboardItem]
    public let resetToken: Int
    public let searchFocusToken: Int
    public let onSelect: (ClipboardItem, ClipboardSelectionAction) -> Void
    public let onFavoriteToggle: (ClipboardItem) -> Void
    public let onTagsChange: (ClipboardItem, [String]) -> Void
    public let onDelete: (ClipboardItem) -> Void
    public let onClear: () -> Void
    public let onDismiss: () -> Void
    private let presentation: ToolModulePresentation

    /// 创建 `MainPanelView`，保存传入依赖并建立初始状态。
    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.resetToken = 0
        self.searchFocusToken = 0
        self.onSelect = { item, _ in onSelect(item) }
        self.onFavoriteToggle = { _ in }
        self.onTagsChange = { _, _ in }
        self.onDelete = { _ in }
        self.onClear = {}
        self.onDismiss = {}
        self.presentation = .window
    }

    /// 创建 `MainPanelView`，保存传入依赖并建立初始状态。
    public init(
        items: [ClipboardItem],
        resetToken: Int = 0,
        searchFocusToken: Int = 0,
        onSelect: @escaping (ClipboardItem, ClipboardSelectionAction) -> Void,
        onFavoriteToggle: @escaping (ClipboardItem) -> Void = { _ in },
        onTagsChange: @escaping (ClipboardItem, [String]) -> Void = { _, _ in },
        onDelete: @escaping (ClipboardItem) -> Void = { _ in },
        onClear: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        presentation: ToolModulePresentation = .window
    ) {
        self.items = items
        self.resetToken = resetToken
        self.searchFocusToken = searchFocusToken
        self.onSelect = onSelect
        self.onFavoriteToggle = onFavoriteToggle
        self.onTagsChange = onTagsChange
        self.onDelete = onDelete
        self.onClear = onClear
        self.onDismiss = onDismiss
        self.presentation = presentation
    }

    @ViewBuilder
    public var body: some View {
        if presentation == .window {
            content
                .liquidGlassWindowPanel(frame: .mainPanel)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let renderState = currentRenderState

        VStack(spacing: 0) {
            header(itemSummary: renderState.itemSummary)

            categoryBar(itemSummary: renderState.itemSummary)

            if mode == .favorites {
                tagFilterBar(itemSummary: renderState.itemSummary)
            }

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .padding(.horizontal, 4)

            clipboardList(renderState: renderState)
                .padding(.top, 6)
        }
        .padding(presentation == .window ? MacToolsControlMetrics.pagePadding : 0)
        .background(KeyboardEventMonitorView(onKeyDown: handleKeyDown))
        .onAppear {
            focusSearchField()
        }
        .onChange(of: items) {
            resetMouseClickConfirmation()
            normalizeTagSelection()
            normalizeSelection()
        }
        .onChange(of: mode) {
            resetMouseClickConfirmation()
            if mode != .favorites {
                selectedTag = nil
            }
            normalizeSelection()
        }
        .onChange(of: selectedTag) {
            resetMouseClickConfirmation()
            normalizeSelection()
        }
        .onChange(of: query) {
            resetMouseClickConfirmation()
            normalizeSelection()
        }
        .onChange(of: resetToken) {
            resetPanelState()
            focusSearchField()
        }
        .onChange(of: searchFocusToken) {
            focusSearchField()
        }
    }

    /// 构建并返回 `clipboardList` 对应的 SwiftUI 界面内容或展示状态。
    private func clipboardList(renderState: ClipboardPanelRenderState) -> some View {
        ClipboardListView(
            items: renderState.filteredItems,
            selectedItemID: renderState.selectedItem?.id,
            mode: mode,
            availableTags: renderState.itemSummary.tagCounts.map(\.name),
            onSelect: handleItemClick,
            onFavoriteToggle: onFavoriteToggle,
            onTagsChange: onTagsChange,
            onDelete: onDelete
        )
        .overlay(alignment: .bottomTrailing) {
            keyboardActions
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
    }

    /// 构建并返回 `header` 对应的 SwiftUI 界面内容或展示状态。
    @ViewBuilder
    private func header(itemSummary: ClipboardPanelItemSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)

            TextField(
                "搜索...",
                text: $query,
                prompt: Text("搜索剪贴板").foregroundColor(MacToolsGlassTheme.textTertiary)
            )
                .textFieldStyle(.plain)
                .font(.system(
                    size: MacToolsControlMetrics.pageTitleFontSize,
                    weight: .medium
                ))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)
                .focused($isSearchFocused)
                .onSubmit {
                    performSelectedAction(.copyAndPaste)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(
                            width: MacToolsControlMetrics.inlineIconSize.width,
                            height: MacToolsControlMetrics.inlineIconSize.height
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(MacToolsGlassTheme.textTertiary)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }

            if let workspaceSidebarChrome {
                sidebarToggleButton(workspaceSidebarChrome)
            }

            Button {
                onClear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(
                        width: MacToolsControlMetrics.toolbarIconSize.width,
                        height: MacToolsControlMetrics.toolbarIconSize.height
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(clearButtonColor(for: itemSummary))
            .liquidGlassButtonStyle(cornerRadius: 14, minimumSize: MacToolsControlMetrics.toolbarIconSize)
            .disabled(!itemSummary.hasClearableItems)
            .opacity(itemSummary.hasClearableItems ? 1 : 0.64)
            .help("清空未收藏的记录")
            .accessibilityLabel("清空未收藏的记录")
        }
        .frame(minHeight: MacToolsControlMetrics.pageHeaderMinimumHeight)
        .padding(.horizontal, 16)
        .liquidGlassGroup(spacing: 12)
    }

    /// 构建并返回 `categoryBar` 对应的 SwiftUI 界面内容或展示状态。
    private func categoryBar(itemSummary: ClipboardPanelItemSummary) -> some View {
        HStack(spacing: 8) {
            ForEach(ClipboardPanelMode.allCases, id: \.self) { itemMode in
                let isSelected = mode == itemMode

                Button {
                    mode = itemMode
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: itemMode.iconName)
                                .foregroundStyle(
                                    isSelected ? MacToolsGlassTheme.selectionBlue : MacToolsGlassTheme.textSecondary
                                )

                            Text(tabTitle(for: itemMode, itemSummary: itemSummary))
                                .foregroundStyle(
                                    isSelected ? MacToolsGlassTheme.selectionBlue : MacToolsGlassTheme.textSecondary
                                )
                        }
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))

                        Capsule()
                            .fill(isSelected ? MacToolsGlassTheme.selectionBlue : Color.clear)
                            .frame(width: 18, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: MacToolsControlMetrics.clipboardCategoryHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ClipboardCategoryButtonStyle(isSelected: isSelected))
                .help("切换到\(itemMode.title)")
                .accessibilityLabel("\(itemMode.title)分类")
                .accessibilityValue(isSelected ? "已选择" : "")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .liquidGlassGroup(spacing: 8)
    }

    /// 构建收藏页的标签快捷筛选条。
    private func tagFilterBar(itemSummary: ClipboardPanelItemSummary) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                tagFilterButton(title: "全部收藏", count: itemSummary.favoriteCount, tag: nil)
                ForEach(itemSummary.tagCounts) { tagCount in
                    tagFilterButton(
                        title: tagCount.name,
                        count: tagCount.count,
                        tag: tagCount.name
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .liquidGlassGroup(spacing: 6)
        }
        .scrollIndicators(.hidden)
    }

    /// 构建单个标签筛选按钮，并保持玻璃节点位置稳定。
    private func tagFilterButton(title: String, count: Int, tag: String?) -> some View {
        let isSelected = selectedTag.map(ClipboardTagPolicy.comparisonKey(for:))
            == tag.map(ClipboardTagPolicy.comparisonKey(for:))

        return Button {
            selectedTag = tag
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
            }
            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(
                isSelected ? MacToolsGlassTheme.selectionBlue : MacToolsGlassTheme.textSecondary
            )
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .liquidGlassButtonHitTarget(cornerRadius: 10)
            .liquidGlassInteractionSurface(
                state: isSelected ? .selected : .idle,
                cornerRadius: 10
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("按标签 \(title) 筛选")
        .accessibilityValue(isSelected ? "已选择" : "")
    }

    /// 构建并返回 `sidebarToggleButton` 对应的 SwiftUI 界面内容或展示状态。
    private func sidebarToggleButton(_ chrome: MainWorkspaceSidebarChrome) -> some View {
        Button {
            chrome.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .semibold))
                .frame(
                    width: MacToolsControlMetrics.toolbarIconSize.width,
                    height: MacToolsControlMetrics.toolbarIconSize.height
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(chrome.isSidebarVisible ? MacToolsGlassTheme.textPrimary : MacToolsGlassTheme.textSecondary)
        .liquidGlassButtonStyle(
            cornerRadius: 14,
            isSelected: chrome.isSidebarVisible,
            minimumSize: MacToolsControlMetrics.toolbarIconSize
        )
        .help(chrome.isSidebarVisible ? "隐藏工具栏" : "显示工具栏")
    }

    private var keyboardActions: some View {
        VStack {
            Button("粘贴选中项") {
                performSelectedAction(.copyAndPaste)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("复制选中项") {
                performSelectedAction(.copy)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var filteredItems: [ClipboardItem] {
        currentRenderState.filteredItems
    }

    private var currentRenderState: ClipboardPanelRenderState {
        ClipboardPanelRenderState(
            items: items,
            mode: mode,
            query: query,
            selectedTag: selectedTag,
            selectedItemID: selectedItemID
        )
    }

    /// 生成分类标签标题；收藏分类额外展示收藏数量。
    private func tabTitle(for mode: ClipboardPanelMode, itemSummary: ClipboardPanelItemSummary) -> String {
        if mode == .favorites {
            return "\(mode.title) (\(itemSummary.favoriteCount))"
        }

        return mode.title
    }

    /// 根据当前是否存在可清理条目返回清除按钮颜色。
    private func clearButtonColor(for itemSummary: ClipboardPanelItemSummary) -> Color {
        itemSummary.hasClearableItems ? MacToolsGlassTheme.textSecondary : MacToolsGlassTheme.textDisabled
    }

    /// 首次点击只选择条目，再次点击同一条目时执行复制并粘贴。
    private func handleItemClick(_ item: ClipboardItem) {
        let clickAction = ClipboardItemClickResolver.action(
            clickedItemID: item.id,
            selectedItemID: selectedItemID,
            armedItemID: armedMouseItemID
        )

        selectedItemID = item.id

        switch clickAction {
        case .select:
            armedMouseItemID = item.id
        case .paste:
            resetMouseClickConfirmation()
            onSelect(item, .copyAndPaste)
        }
    }

    /// 对当前选中条目执行复制或复制并粘贴，并清除鼠标二次点击确认。
    private func performSelectedAction(_ action: ClipboardSelectionAction) {
        guard let item = selectedItem else {
            return
        }

        resetMouseClickConfirmation()
        onSelect(item, action)
    }

    /// 在当前过滤结果内移动选择，索引到达首尾时停止而不循环。
    private func moveSelection(by offset: Int) {
        resetMouseClickConfirmation()
        let visibleItems = filteredItems
        guard !visibleItems.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = selectedItemID.flatMap { selectedItemID in
            visibleItems.firstIndex(where: { $0.id == selectedItemID })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visibleItems.count - 1)
        selectedItemID = visibleItems[nextIndex].id
    }

    /// 按键盘方向切换相邻剪贴板分类。
    private func moveMode(_ direction: ClipboardPanelModeNavigationDirection) {
        mode = ClipboardPanelModeNavigator.mode(adjacentTo: mode, direction: direction)
    }

    /// 保留仍可见的选择；选择消失时回退到过滤结果第一项。
    private func normalizeSelection() {
        let visibleItems = filteredItems
        guard !visibleItems.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID,
           visibleItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = visibleItems.first?.id
    }

    /// 标签不存在时回退到全部收藏，避免保留不可见筛选条件。
    private func normalizeTagSelection() {
        guard let selectedTag,
              currentRenderState.itemSummary.containsTag(selectedTag) else {
            self.selectedTag = nil
            return
        }
    }

    /// 将当前过滤结果的第一项设为键盘选择项。
    private func selectFirstItem() {
        selectedItemID = filteredItems.first?.id
    }

    /// 清空搜索与分类状态，并选择重置后列表的第一项。
    private func resetPanelState() {
        query = ""
        mode = .all
        selectedTag = nil
        resetMouseClickConfirmation()
        selectFirstItem()
    }

    /// 清除需要二次点击才能粘贴的鼠标武装条目。
    private func resetMouseClickConfirmation() {
        armedMouseItemID = nil
    }

    /// 在下一次主 Actor 调度中把焦点移到搜索框。
    private func focusSearchField() {
        Task { @MainActor in
            isSearchFocused = true
        }
    }

    /// 将 Escape、分类切换、确认和上下选择按键映射为面板操作。
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if PanelKeyCommandResolver().command(forKeyCode: event.keyCode) == .dismiss {
            onDismiss()
            return true
        }

        if let direction = ClipboardPanelModeNavigator.direction(forKeyCode: event.keyCode) {
            moveMode(direction)
            return true
        }

        switch event.keyCode {
        case 36, 76:
            performSelectedAction(event.modifierFlags.contains(.command) ? .copy : .copyAndPaste)
            return true
        case 125:
            moveSelection(by: 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        default:
            return false
        }
    }

    private var selectedItem: ClipboardItem? {
        currentRenderState.selectedItem
    }
}

/// 封装 `ClipboardCategoryButtonStyle` 在 SwiftUI 展示层中的值语义和相关操作。
private struct ClipboardCategoryButtonStyle: ButtonStyle {
    let isSelected: Bool

    /// 构造并返回 `makeBody` 所描述的 SwiftUI 展示层对象。
    func makeBody(configuration: Configuration) -> some View {
        let presentation = ClipboardCategoryButtonPresentation(
            isSelected: isSelected,
            isPressed: configuration.isPressed
        )

        configuration.label
            .frame(
                minWidth: MacToolsControlMetrics.clipboardCategoryMinimumWidth,
                minHeight: MacToolsControlMetrics.clipboardCategoryHeight
            )
            .liquidGlassButtonHitTarget(cornerRadius: 12)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .liquidGlassStableFloatingSelection(
                cornerRadius: 12,
                isVisible: presentation.interactionState == .selected
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 将分类按钮状态映射到固定位置的 Liquid Glass 节点。
struct ClipboardCategoryButtonPresentation: Equatable {
    let interactionState: LiquidGlassInteractionState

    init(isSelected: Bool, isPressed: Bool) {
        self.interactionState = isSelected || isPressed ? .selected : .idle
    }
}

/// 只让主面板窗口处理自己的按键，避免 Popover 输入被分类快捷键截获。
enum ClipboardKeyboardEventRoutingPolicy {
    static func shouldHandle(eventWindowNumber: Int, panelWindowNumber: Int) -> Bool {
        eventWindowNumber == panelWindowNumber
    }
}

/// 封装 `KeyboardEventMonitorView` 在 SwiftUI 展示层中的值语义和相关操作。
private struct KeyboardEventMonitorView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    /// 构造并返回 `makeNSView` 所描述的 SwiftUI 展示层对象。
    func makeNSView(context: Context) -> KeyboardEventMonitorNSView {
        let view = KeyboardEventMonitorNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    /// 更新键盘事件回调，并保持底层 NSView 实例不变。
    func updateNSView(_ nsView: KeyboardEventMonitorNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

/// 管理 `KeyboardEventMonitorNSView` 在 SwiftUI 展示层中的生命周期、依赖和可变状态。
private final class KeyboardEventMonitorNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    private var monitor: Any?

    /// 视图进入窗口后注册本地键盘监听，并把事件交给 SwiftUI 回调。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isVisible,
                  ClipboardKeyboardEventRoutingPolicy.shouldHandle(
                      eventWindowNumber: event.windowNumber,
                      panelWindowNumber: window.windowNumber
                  ),
                  self.onKeyDown?(event) == true else {
                return event
            }

            return nil
        }
    }

    /// 视图离开窗口前移除本地事件监听，避免重复回调和资源泄漏。
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
