import SwiftUI

public enum ClipboardSelectionAction {
    case copy
    case copyAndPaste
}

public struct MainPanelView: View {
    @State private var query = ""
    @State private var selectedItemID: ClipboardItem.ID?

    public let items: [ClipboardItem]
    public let onSelect: (ClipboardItem, ClipboardSelectionAction) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = { item, _ in onSelect(item) }
    }

    public init(
        items: [ClipboardItem],
        onSelect: @escaping (ClipboardItem, ClipboardSelectionAction) -> Void
    ) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("Search tools and clipboard", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .padding(16)

            Divider()

            ClipboardListView(items: filteredItems, onSelect: selectAndPaste)
                .overlay(alignment: .bottomTrailing) {
                    keyboardActions
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
        }
        .frame(width: 760, height: 520)
    }

    private var keyboardActions: some View {
        VStack {
            Button("Paste Selection") {
                performSelectedAction(.copyAndPaste)
            }
            .keyboardShortcut(.return, modifiers: [])

            Button("Copy Selection") {
                performSelectedAction(.copy)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var filteredItems: [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return items
        }

        return items.filter { item in
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

    private var selectedItem: ClipboardItem? {
        if let selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID }) {
            return item
        }

        return filteredItems.first
    }
}
