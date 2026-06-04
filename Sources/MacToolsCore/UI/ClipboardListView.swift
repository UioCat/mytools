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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardRowView(
                                item: item,
                                index: index + 1,
                                isSelected: item.id == selectedItemID,
                                onFavoriteToggle: {
                                    onFavoriteToggle(item)
                                }
                            )
                            .id(item.id)
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

                                Divider()

                                Button("删除", role: .destructive) {
                                    onDelete(item)
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedItemID) { id in
                guard let id else {
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)

            Text("没有匹配的剪贴板内容")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}
