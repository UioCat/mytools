import SwiftUI

public struct ClipboardRowView: View {
    public let item: ClipboardItem

    public init(item: ClipboardItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(sourceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.isPinned {
                StatusLabel(title: "Pinned")
            }

            if item.isFavorite {
                StatusLabel(title: "Favorite")
            }
        }
        .padding(.vertical, 6)
    }

    private var iconName: String {
        switch item.kind {
        case .text:
            return "doc.text"
        case .url:
            return "link"
        case .file:
            return "doc"
        case .folder:
            return "folder"
        case .imageFile, .imageData:
            return "photo"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var sourceLabel: String {
        if let sourceApp = item.sourceApp, !sourceApp.isEmpty {
            return "\(sourceApp) - \(item.kind.rawValue)"
        }

        return item.kind.rawValue
    }
}

private struct StatusLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}
