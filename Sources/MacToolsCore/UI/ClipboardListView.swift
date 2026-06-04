import SwiftUI

public struct ClipboardListView: View {
    public let items: [ClipboardItem]
    public let onSelect: (ClipboardItem) -> Void

    public init(items: [ClipboardItem], onSelect: @escaping (ClipboardItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        List(items) { item in
            Button {
                onSelect(item)
            } label: {
                ClipboardRowView(item: item)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }
}
