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
                LazyVStack(spacing: 10) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let isSelected = item.id == selectedItemID

                            ClipboardRowView(
                                item: item,
                                index: index + 1,
                                isSelected: isSelected,
                                showsBackground: isSelected,
                                onFavoriteToggle: {
                                    onFavoriteToggle(item)
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .onTapGesture {
                                onSelect(item)
                            }
                            .id(item.id)
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
                .padding(.vertical, 2)
                .liquidGlassGroup(spacing: 10)
            }
            .background(Color.clear)
            .onChange(of: selectedItemID) { id in
                guard let id else {
                    return
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(
                        id,
                        anchor: ClipboardListScrollAnchorPolicy.anchor(for: id, in: items).unitPoint
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.58))

            Text("没有匹配的剪贴板内容")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.64))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
        .liquidGlassModule(cornerRadius: 24)
    }
}

enum ClipboardListScrollAnchor: Equatable {
    case top
    case center
    case bottom

    var unitPoint: UnitPoint {
        switch self {
        case .top:
            return .top
        case .center:
            return .center
        case .bottom:
            return .bottom
        }
    }
}

enum ClipboardListScrollAnchorPolicy {
    static func anchor(for selectedItemID: ClipboardItem.ID, in items: [ClipboardItem]) -> ClipboardListScrollAnchor {
        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedItemID }) else {
            return .center
        }

        if selectedIndex == items.startIndex {
            return .top
        }

        if selectedIndex == items.index(before: items.endIndex) {
            return .bottom
        }

        return .center
    }
}
