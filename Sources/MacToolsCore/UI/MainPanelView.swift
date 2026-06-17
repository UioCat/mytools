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
    case folders
    case favorites

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .text:
            return "文本"
        case .images:
            return "图片"
        case .folders:
            return "文件夹"
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
        case .folders:
            return "folder"
        case .favorites:
            return "star.fill"
        }
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
        case .folders:
            modeItems = items.filter { $0.kind == .folder }
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

public struct MainPanelView: View {
    @Environment(\.mainWorkspaceSidebarChrome) private var workspaceSidebarChrome
    @State private var query = ""
    @State private var selectedItemID: ClipboardItem.ID?
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

        VStack(spacing: 12) {
            header(itemSummary: renderState.itemSummary)

            modeSwitcher(itemSummary: renderState.itemSummary)

            clipboardContentArea(renderState: renderState)
        }
        .padding(18)
        .background(KeyboardEventMonitorView(onKeyDown: handleKeyDown))
        .onAppear {
            focusSearchField()
        }
        .onChange(of: items) { _ in
            normalizeSelection()
        }
        .onChange(of: mode) { _ in
            normalizeSelection()
        }
        .onChange(of: query) { _ in
            normalizeSelection()
        }
        .onChange(of: resetToken) { _ in
            resetPanelState()
            focusSearchField()
        }
        .onChange(of: searchFocusToken) { _ in
            focusSearchField()
        }
    }

    private func clipboardContentArea(renderState: ClipboardPanelRenderState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                clipboardList(renderState: renderState)
                    .frame(minWidth: 0, maxWidth: .infinity)

                clipboardDetailPane(selectedItem: renderState.selectedItem)
                    .frame(width: 292)
            }

            clipboardList(renderState: renderState)
        }
    }

    private func clipboardList(renderState: ClipboardPanelRenderState) -> some View {
        ClipboardListView(
            items: renderState.filteredItems,
            selectedItemID: renderState.selectedItem?.id,
            mode: mode,
            onSelect: selectAndPaste,
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
    private func clipboardDetailPane(selectedItem: ClipboardItem?) -> some View {
        if let selectedItem {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconBadge(systemName: iconName(for: selectedItem), size: 46, iconSize: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedItem.displayTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(MacToolsGlassTheme.textPrimary)
                            .lineLimit(2)

                        Text(detailMetric(for: selectedItem))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Text(detailPreview(for: selectedItem))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineSpacing(4)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(MacToolsGlassTheme.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(MacToolsGlassTheme.border, lineWidth: 1)
                    )

                VStack(spacing: 10) {
                    Button {
                        onSelect(selectedItem, .copyAndPaste)
                    } label: {
                        Label("粘贴", systemImage: "clipboard")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassPrimaryButtonStyle(cornerRadius: 14))

                    detailSecondaryButton(title: "复制", systemImage: "doc.on.doc") {
                        onSelect(selectedItem, .copy)
                    }

                    detailSecondaryButton(
                        title: selectedItem.isFavorite ? "取消收藏" : "收藏",
                        systemImage: selectedItem.isFavorite ? "star.slash" : "star"
                    ) {
                        onFavoriteToggle(selectedItem)
                    }

                    detailSecondaryButton(
                        title: "删除",
                        systemImage: "trash",
                        foreground: MacToolsGlassTheme.destructive
                    ) {
                        onDelete(selectedItem)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .liquidGlassModule(cornerRadius: 24)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)

                Text("选择一条记录查看详情")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .padding(18)
            .liquidGlassModule(cornerRadius: 24)
        }
    }

    private func detailSecondaryButton(
        title: String,
        systemImage: String,
        foreground: Color = MacToolsGlassTheme.textPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .foregroundStyle(foreground)
        .liquidGlassButtonStyle(cornerRadius: 14)
    }

    @ViewBuilder
    private func header(itemSummary: ClipboardPanelItemSummary) -> some View {
        HStack(spacing: 14) {
            if let workspaceSidebarChrome {
                sidebarToggleButton(workspaceSidebarChrome)
            }

            TextField(
                "搜索...",
                text: $query,
                prompt: Text("搜索剪贴板").foregroundColor(MacToolsGlassTheme.textTertiary)
            )
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)
                .focused($isSearchFocused)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .liquidGlassInteractiveModule(cornerRadius: 24)
                .onSubmit {
                    performSelectedAction(.copyAndPaste)
                }

            Button {
                onClear()
            } label: {
                Label("清空", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 56)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .foregroundStyle(clearButtonColor(for: itemSummary))
            .liquidGlassButtonStyle(cornerRadius: 22)
            .disabled(!itemSummary.hasClearableItems)
            .opacity(itemSummary.hasClearableItems ? 1 : 0.64)
        }
        .liquidGlassGroup(spacing: 14)
    }

    private func sidebarToggleButton(_ chrome: MainWorkspaceSidebarChrome) -> some View {
        Button {
            chrome.toggleSidebar()
        } label: {
            Image(systemName: chrome.isSidebarVisible ? "sidebar.left" : "sidebar.left")
                .font(.system(size: 16, weight: .semibold))
                .frame(
                    width: MainWorkspaceLayout.collapsedSidebarToggleSize.width,
                    height: MainWorkspaceLayout.collapsedSidebarToggleSize.height
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .foregroundStyle(chrome.isSidebarVisible ? MacToolsGlassTheme.textPrimary : MacToolsGlassTheme.textSecondary)
        .liquidGlassButtonStyle(
            cornerRadius: 18,
            isSelected: chrome.isSidebarVisible,
            minimumSize: MainWorkspaceLayout.collapsedSidebarToggleSize
        )
        .help(chrome.isSidebarVisible ? "隐藏工具栏" : "显示工具栏")
    }

    @ViewBuilder
    private func modeSwitcher(itemSummary: ClipboardPanelItemSummary) -> some View {
        HStack(spacing: 10) {
            ForEach(ClipboardPanelMode.allCases, id: \.self) { itemMode in
                Button {
                    mode = itemMode
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: itemMode.iconName)
                            .font(.system(size: 15, weight: .semibold))

                        Text(tabTitle(for: itemMode, itemSummary: itemSummary))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .foregroundStyle(mode == itemMode ? MacToolsGlassTheme.textPrimary : MacToolsGlassTheme.textSecondary)
                .liquidGlassButtonStyle(cornerRadius: 20, isSelected: mode == itemMode)
            }
        }
        .liquidGlassGroup(spacing: 10)
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

    private func iconName(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .file:
            return "doc"
        case .folder:
            return "folder"
        case .imageFile, .imageData:
            return "photo"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func detailMetric(for item: ClipboardItem) -> String {
        let relativeTime = relativeCreatedAt(for: item)
        let metric: String
        switch item.kind {
        case .text, .url:
            metric = "\(item.searchableText.count) 字符"
        case .file:
            metric = "文件"
        case .folder:
            metric = "文件夹"
        case .imageFile, .imageData:
            metric = "图片"
        case .unknown:
            metric = "未知类型"
        }

        return "\(relativeTime) · \(metric)"
    }

    private func detailPreview(for item: ClipboardItem) -> String {
        let candidates = [
            item.text,
            item.originalPath,
            item.searchableText.isEmpty ? nil : item.searchableText,
            item.displayTitle
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "暂无可预览内容"
    }

    private func relativeCreatedAt(for item: ClipboardItem) -> String {
        let elapsed = max(0, Date().timeIntervalSince(item.createdAt))

        if elapsed < 60 {
            return "刚刚"
        }

        if elapsed < 3600 {
            return "\(Int(elapsed / 60)) 分钟前"
        }

        if elapsed < 86400 {
            return "\(Int(elapsed / 3600)) 小时前"
        }

        return "\(Int(elapsed / 86400)) 天前"
    }

    private func clearButtonColor(for itemSummary: ClipboardPanelItemSummary) -> Color {
        itemSummary.hasClearableItems ? MacToolsGlassTheme.textSecondary : MacToolsGlassTheme.textDisabled
    }

    private func selectAndPaste(_ item: ClipboardItem) {
        selectedItemID = item.id
        onSelect(item, .copyAndPaste)
    }

    private func performSelectedAction(_ action: ClipboardSelectionAction) {
        guard let item = selectedItem else {
            return
        }

        onSelect(item, action)
    }

    private func moveSelection(by offset: Int) {
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

    private func switchMode(by offset: Int) {
        let modes = ClipboardPanelMode.allCases
        guard let currentIndex = modes.firstIndex(of: mode) else {
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), modes.count - 1)
        mode = modes[nextIndex]
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
        selectFirstItem()
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

        switch event.keyCode {
        case 36, 76:
            performSelectedAction(event.modifierFlags.contains(.command) ? .copy : .copyAndPaste)
            return true
        case 123:
            switchMode(by: -1)
            return true
        case 124:
            switchMode(by: 1)
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

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
