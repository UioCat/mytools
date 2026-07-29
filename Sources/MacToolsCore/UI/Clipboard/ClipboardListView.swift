// 剪贴板历史的过滤、选择和滚动列表。
// 负责可见列表状态与键盘导航，数据变更通过调用方闭包提交。

import SwiftUI

/// 封装 `ClipboardListView` 在 SwiftUI 展示层中的值语义和相关操作。
public struct ClipboardListView: View {
    public let items: [ClipboardItem]
    public let selectedItemID: ClipboardItem.ID?
    public let mode: ClipboardPanelMode
    public let onSelect: (ClipboardItem) -> Void
    public let onFavoriteToggle: (ClipboardItem) -> Void
    public let onDelete: (ClipboardItem) -> Void

    /// 创建 `ClipboardListView`，保存传入依赖并建立初始状态。
    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.selectedItemID = nil
        self.mode = .all
        self.onSelect = onSelect
        self.onFavoriteToggle = { _ in }
        self.onDelete = { _ in }
    }

    /// 创建 `ClipboardListView`，保存传入依赖并建立初始状态。
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
                LazyVStack(spacing: 2) {
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
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                .padding(.vertical, 4)
                .liquidGlassGroup(spacing: 2)
            }
            .background(Color.clear)
            .task(id: selectedItemID) { @MainActor in
                // 键盘选择变化与 LazyVStack 创建新可见行可能发生在同一轮更新中。
                // 先等待布局完成再要求 proxy 滚动；用户连续按方向键时，
                // task(id:) 还会自动取消上一条过期滚动请求。
                await Task.yield()

                guard !Task.isCancelled else {
                    return
                }

                let id = selectedItemID
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
                .foregroundStyle(MacToolsGlassTheme.textTertiary)

            Text("没有匹配的剪贴板内容")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }
}

/// 描述 `ClipboardListScrollAnchor` 在 SwiftUI 展示层中可取的状态、选项或错误。
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

/// 描述 `ClipboardListScrollAnchorPolicy` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum ClipboardListScrollAnchorPolicy {
    /// 构建并返回 `anchor` 对应的 SwiftUI 界面内容或展示状态。
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
