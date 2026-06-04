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
            return "textformat"
        case .images:
            return "photo"
        case .folders:
            return "folder"
        case .favorites:
            return "star.fill"
        }
    }
}

public struct MainPanelView: View {
    @State private var query = ""
    @State private var selectedItemID: ClipboardItem.ID?
    @State private var mode: ClipboardPanelMode = .all

    public let items: [ClipboardItem]
    public let onSelect: (ClipboardItem, ClipboardSelectionAction) -> Void
    public let onFavoriteToggle: (ClipboardItem) -> Void
    public let onDelete: (ClipboardItem) -> Void
    public let onClear: () -> Void
    public let onDismiss: () -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = { item, _ in onSelect(item) }
        self.onFavoriteToggle = { _ in }
        self.onDelete = { _ in }
        self.onClear = {}
        self.onDismiss = {}
    }

    public init(
        items: [ClipboardItem],
        onSelect: @escaping (ClipboardItem, ClipboardSelectionAction) -> Void,
        onFavoriteToggle: @escaping (ClipboardItem) -> Void = { _ in },
        onDelete: @escaping (ClipboardItem) -> Void = { _ in },
        onClear: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onFavoriteToggle = onFavoriteToggle
        self.onDelete = onDelete
        self.onClear = onClear
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            modeSwitcher
                .padding(.horizontal, 6)

            Divider()

            ClipboardListView(
                items: filteredItems,
                selectedItemID: selectedItem?.id,
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
        .background(KeyboardEventMonitorView(onKeyDown: handleKeyDown))
        .frame(width: 900, height: 620)
        .onChange(of: items) { _ in
            normalizeSelection()
        }
        .onChange(of: mode) { _ in
            normalizeSelection()
        }
        .onChange(of: query) { _ in
            normalizeSelection()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))

                Text("剪贴板")
                    .font(.system(size: 22, weight: .semibold))
            }

            Divider()
                .frame(height: 28)

            TextField("搜索...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))

            Button {
                onClear()
            } label: {
                Label("清空", systemImage: "trash")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(clearButtonColor)
            .disabled(items.filter { !$0.isFavorite }.isEmpty)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(ClipboardPanelMode.allCases, id: \.self) { itemMode in
                Button {
                    mode = itemMode
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: itemMode.iconName)
                            .font(.system(size: 15, weight: .semibold))

                        Text(tabTitle(for: itemMode))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == itemMode ? Color.primary : Color.secondary)
                .background(
                    mode == itemMode ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
        }
        .padding(.bottom, 2)
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

    private func tabTitle(for mode: ClipboardPanelMode) -> String {
        if mode == .favorites {
            return "\(mode.title) (\(items.filter(\.isFavorite).count))"
        }

        return mode.title
    }

    private var clearButtonColor: Color {
        items.contains(where: { !$0.isFavorite }) ? Color.secondary : Color.secondary.opacity(0.45)
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
        guard !filteredItems.isEmpty else {
            selectedItemID = nil
            return
        }

        let currentIndex = selectedItem.flatMap { selected in
            filteredItems.firstIndex(where: { $0.id == selected.id })
        } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        selectedItemID = filteredItems[nextIndex].id
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
        guard !filteredItems.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        selectedItemID = filteredItems.first?.id
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 36, 76:
            performSelectedAction(event.modifierFlags.contains(.command) ? .copy : .copyAndPaste)
            return true
        case 53:
            onDismiss()
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
        if let selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID }) {
            return item
        }

        return filteredItems.first
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
