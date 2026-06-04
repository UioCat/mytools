import SwiftUI

public struct MainPanelView: View {
    @State private var query = ""

    public let items: [ClipboardItem]
    public let onSelect: (ClipboardItem) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
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

            ClipboardListView(items: filteredItems, onSelect: onSelect)
        }
        .frame(width: 760, height: 520)
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
}
