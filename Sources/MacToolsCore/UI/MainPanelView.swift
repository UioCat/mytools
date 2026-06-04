import AppKit
import SwiftUI

public enum ClipboardSelectionAction {
    case copy
    case copyAndPaste
}

public enum ClipboardPanelMode: CaseIterable {
    case all
    case favorites

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .favorites:
            return "收藏"
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
    public let onDismiss: () -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = { item, _ in onSelect(item) }
        self.onFavoriteToggle = { _ in }
        self.onDismiss = {}
    }

    public init(
        items: [ClipboardItem],
        onSelect: @escaping (ClipboardItem, ClipboardSelectionAction) -> Void,
        onFavoriteToggle: @escaping (ClipboardItem) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.items = items
        self.onSelect = onSelect
        self.onFavoriteToggle = onFavoriteToggle
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("搜索工具和剪贴板", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .padding(16)

            modeSwitcher
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()

            ClipboardListView(
                items: filteredItems,
                selectedItemID: selectedItem?.id,
                onSelect: selectAndPaste,
                onFavoriteToggle: onFavoriteToggle
            )
                .overlay(alignment: .bottomTrailing) {
                    keyboardActions
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
        }
        .background(KeyboardEventMonitorView(onKeyDown: handleKeyDown))
        .frame(width: 760, height: 520)
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

    private var modeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(ClipboardPanelMode.allCases, id: \.self) { itemMode in
                Button {
                    mode = itemMode
                } label: {
                    Text(itemMode.title)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 52, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(mode == itemMode ? .white : .secondary)
                .background(
                    mode == itemMode ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }

            Spacer()

            Text("↑↓ 选择  ←→ 切换  Enter 粘贴  ⌘Enter 复制  Esc 关闭")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
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
