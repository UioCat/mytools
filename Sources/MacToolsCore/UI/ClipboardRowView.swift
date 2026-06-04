import AppKit
import SwiftUI

public struct ClipboardRowView: View {
    public let item: ClipboardItem
    public let isSelected: Bool
    public let onFavoriteToggle: () -> Void

    public init(item: ClipboardItem) {
        self.item = item
        self.isSelected = false
        self.onFavoriteToggle = {}
    }

    public init(
        item: ClipboardItem,
        isSelected: Bool,
        onFavoriteToggle: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onFavoriteToggle = onFavoriteToggle
    }

    public var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: 44, height: 44)

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
                StatusLabel(title: "置顶")
            }

            if item.isFavorite {
                StatusLabel(title: "收藏")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                )
        } else {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var previewImage: NSImage? {
        guard item.kind == .imageData || item.kind == .imageFile else {
            return nil
        }

        guard let path = item.cachedFilePath ?? item.originalPath else {
            return nil
        }

        return NSImage(contentsOfFile: path)
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
            return "\(sourceApp) - \(kindTitle)"
        }

        return kindTitle
    }

    private var kindTitle: String {
        switch item.kind {
        case .text:
            return "文本"
        case .url:
            return "链接"
        case .file:
            return "文件"
        case .folder:
            return "文件夹"
        case .imageFile:
            return "图片文件"
        case .imageData:
            return "图片"
        case .unknown:
            return "未知"
        }
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
