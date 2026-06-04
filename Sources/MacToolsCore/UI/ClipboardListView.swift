import SwiftUI

public struct ClipboardListView: View {
    public let items: [ClipboardItem]
    public let selectedItemID: ClipboardItem.ID?
    public let onSelect: (ClipboardItem) -> Void
    public let onFavoriteToggle: (ClipboardItem) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.selectedItemID = nil
        self.onSelect = onSelect
        self.onFavoriteToggle = { _ in }
    }

    public init(
        items: [ClipboardItem],
        selectedItemID: ClipboardItem.ID?,
        onSelect: @escaping (ClipboardItem) -> Void,
        onFavoriteToggle: @escaping (ClipboardItem) -> Void
    ) {
        self.items = items
        self.selectedItemID = selectedItemID
        self.onSelect = onSelect
        self.onFavoriteToggle = onFavoriteToggle
    }

    public var body: some View {
        List(items) { item in
            ClipboardRowView(
                item: item,
                isSelected: item.id == selectedItemID,
                onFavoriteToggle: {
                    onFavoriteToggle(item)
                }
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(item)
            }
        }
        .listStyle(.plain)
    }
}
