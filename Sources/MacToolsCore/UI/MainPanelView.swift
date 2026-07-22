import AppKit
import SwiftUI

public enum ClipboardSelectionAction {
    case copy
    case copyAndPaste
}

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

enum ClipboardPanelModeNavigationDirection: Equatable {
    case previous
    case next
}

enum ClipboardPanelModeNavigator {
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

struct ClipboardPanelItemSummary: Equatable {
    let favoriteCount: Int
    let hasClearableItems: Bool

    init(items: [ClipboardItem]) {
        var favoriteCount = 0
        var hasClearableItems = false

        for item in items {
            if item.isFavorite {
                favoriteCount += 1
            } else {
                hasClearableItems = true
            }
        }

        self.favoriteCount = favoriteCount
        self.hasClearableItems = hasClearableItems
    }
}

struct ClipboardPanelRenderState {
    let itemSummary: ClipboardPanelItemSummary
    let filteredItems: [ClipboardItem]
    let selectedItem: ClipboardItem?

    init(
        items: [ClipboardItem],
        mode: ClipboardPanelMode,
        query: String,
        selectedItemID: ClipboardItem.ID?
    ) {
        self.itemSummary = ClipboardPanelItemSummary(items: items)
        self.filteredItems = Self.filteredItems(items: items, mode: mode, query: query)
        self.selectedItem = Self.selectedItem(in: filteredItems, selectedItemID: selectedItemID)
    }

    static func filteredItems(
        items: [ClipboardItem],
        mode: ClipboardPanelMode,
        query: String
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

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return modeItems
        }

        return modeItems.filter { item in
            item.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                || item.searchableText.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

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

enum ClipboardItemClickAction: Equatable {
    case select
    case paste
}

enum ClipboardItemClickResolver {
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

public struct MainPanelView: View {
    @Environment(\.mainWorkspaceSidebarChrome) private var workspaceSidebarChrome
    @State private var query = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var armedMouseItemID: ClipboardItem.ID?
    @State private var mode: ClipboardPanelMode = .all
    @FocusState private var isSearchFocused: Bool

    public let items: [ClipboardItem]
    public let resetToken: Int
    public let searchFocusToken: Int
    public let onSelect: (ClipboardItem, ClipboardSelectionAction) -> Void
    public let onFavoriteToggle: (ClipboardItem) -> Void
    public let onDelete: (ClipboardItem) -> Void
    public let onClear: () -> Void
    public let onDismiss: () -> Void
    private let presentation: ToolModulePresentation

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.resetToken = 0
        self.searchFocusToken = 0
        self.onSelect = { item, _ in onSelect(item) }
        self.onFavoriteToggle = { _ in }
        self.onDelete = { _ in }
        self.onClear = {}
        self.onDismiss = {}
        self.presentation = .window
    }

    public init(
        items: [ClipboardItem],
        resetToken: Int = 0,
        searchFocusToken: Int = 0,
        onSelect: @escaping (ClipboardItem, ClipboardSelectionAction) -> Void,
        onFavoriteToggle: @escaping (ClipboardItem) -> Void = { _ in },
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

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .padding(.horizontal, 4)

            clipboardList(renderState: renderState)
                .padding(.top, 6)
        }
        .padding(presentation == .window ? 18 : 0)
        .background(KeyboardEventMonitorView(onKeyDown: handleKeyDown))
        .onAppear {
            focusSearchField()
        }
        .onChange(of: items) {
            resetMouseClickConfirmation()
            normalizeSelection()
        }
        .onChange(of: mode) {
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

    private func clipboardList(renderState: ClipboardPanelRenderState) -> some View {
        ClipboardListView(
            items: renderState.filteredItems,
            selectedItemID: renderState.selectedItem?.id,
            mode: mode,
            onSelect: handleItemClick,
            onFavoriteToggle: onFavoriteToggle,
            onDelete: onDelete
        )
        .overlay(alignment: .bottomTrailing) {
            keyboardActions
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
    }

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
                .font(.system(size: 26, weight: .medium))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .liquidGlassGroup(spacing: 12)
    }

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
            selectedItemID: selectedItemID
        )
    }

    private func tabTitle(for mode: ClipboardPanelMode, itemSummary: ClipboardPanelItemSummary) -> String {
        if mode == .favorites {
            return "\(mode.title) (\(itemSummary.favoriteCount))"
        }

        return mode.title
    }

    private func clearButtonColor(for itemSummary: ClipboardPanelItemSummary) -> Color {
        itemSummary.hasClearableItems ? MacToolsGlassTheme.textSecondary : MacToolsGlassTheme.textDisabled
    }

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

    private func performSelectedAction(_ action: ClipboardSelectionAction) {
        guard let item = selectedItem else {
            return
        }

        resetMouseClickConfirmation()
        onSelect(item, action)
    }

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

    private func moveMode(_ direction: ClipboardPanelModeNavigationDirection) {
        mode = ClipboardPanelModeNavigator.mode(adjacentTo: mode, direction: direction)
    }

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

    private func selectFirstItem() {
        selectedItemID = filteredItems.first?.id
    }

    private func resetPanelState() {
        query = ""
        mode = .all
        resetMouseClickConfirmation()
        selectFirstItem()
    }

    private func resetMouseClickConfirmation() {
        armedMouseItemID = nil
    }

    private func focusSearchField() {
        Task { @MainActor in
            isSearchFocused = true
        }
    }

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

private struct ClipboardCategoryButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                minWidth: MacToolsControlMetrics.clipboardCategoryMinimumWidth,
                minHeight: MacToolsControlMetrics.clipboardCategoryHeight
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .modifier(
                ClipboardCategoryButtonSurfaceModifier(
                    isVisible: isSelected || configuration.isPressed
                )
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct ClipboardCategoryButtonSurfaceModifier: ViewModifier {
    let isVisible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isVisible {
            content.liquidGlassFloatingSelection(cornerRadius: 12)
        } else {
            content
        }
    }
}

private struct KeyboardEventMonitorView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyboardEventMonitorNSView {
        let view = KeyboardEventMonitorNSView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ nsView: KeyboardEventMonitorNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

private final class KeyboardEventMonitorNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.window?.isVisible == true,
                  self.onKeyDown?(event) == true else {
                return event
            }

            return nil
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
