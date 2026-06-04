import SwiftUI

public struct ClipboardListView: View {
    public let items: [ClipboardItem]
    public let selectedItemID: ClipboardItem.ID?
    public let mode: ClipboardPanelMode
    public let onSelect: (ClipboardItem) -> Void
    public let onFavoriteToggle: (ClipboardItem) -> Void
    public let onDelete: (ClipboardItem) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.selectedItemID = nil
        self.mode = .all
        self.onSelect = onSelect
        self.onFavoriteToggle = { _ in }
        self.onDelete = { _ in }
    }

    public init(
        items: [ClipboardItem],
        selectedItemID: ClipboardItem.ID?,
        mode: ClipboardPanelMode,
        onSelect: @escaping (ClipboardItem) -> Void,
        onFavoriteToggle: @escaping (ClipboardItem) -> Void,
        onDelete: @escaping (ClipboardItem) -> Void
    ) {
        self.items = items
        self.selectedItemID = selectedItemID
        self.mode = mode
        self.onSelect = onSelect
        self.onFavoriteToggle = onFavoriteToggle
        self.onDelete = onDelete
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
            .contextMenu {
                if mode == .favorites {
                    Button("取消收藏") {
                        onFavoriteToggle(item)
                    }
                } else {
                    Button(item.isFavorite ? "取消收藏" : "加入收藏") {
                        onFavoriteToggle(item)
                    }
                }

                Button("删除") {
                    onDelete(item)
                }
            }
        }
        .listStyle(.plain)
    }
}
