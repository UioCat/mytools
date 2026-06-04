import AppKit
import SwiftUI

public struct ClipboardRowView: View {
    public let item: ClipboardItem
    public let index: Int
    public let isSelected: Bool
    public let onFavoriteToggle: () -> Void

    public init(item: ClipboardItem) {
        self.item = item
        self.index = 1
        self.isSelected = false
        self.onFavoriteToggle = {}
    }

    public init(
        item: ClipboardItem,
        index: Int = 1,
        isSelected: Bool,
        onFavoriteToggle: @escaping () -> Void
    ) {
        self.item = item
        self.index = index
        self.isSelected = isSelected
        self.onFavoriteToggle = onFavoriteToggle
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.displayTitle)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(isImage ? 1 : 2)

                    Spacer(minLength: 12)

                    if !isImage {
                        Text(primaryMetric)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("\(index)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }

                if isImage {
                    imagePreview
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                }

                HStack(spacing: 8) {
                    Text(relativeCreatedAt)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    if item.isPinned {
                        StatusLabel(title: "置顶")
                    }

                    if item.isFavorite {
                        StatusLabel(title: "收藏")
                    }

                    Spacer(minLength: 12)

                    if isImage {
                        Text(primaryMetric)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, isImage ? 14 : 12)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(selectedOverlay)
            .padding(.horizontal, 14)
            .padding(.vertical, 3)

            Rectangle()
                .fill(Color.primary.opacity(0.11))
                .frame(height: 1)
                .padding(.horizontal, 28)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 8)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var previewImage: NSImage? {
        guard item.kind == .imageData || item.kind == .imageFile else {
            return nil
        }

        guard let path = item.thumbnailPath ?? item.cachedFilePath ?? item.originalPath else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }

    private var isImage: Bool {
        item.kind == .imageData || item.kind == .imageFile
    }

    private var rowBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.white.opacity(0.001))
    }

    @ViewBuilder
    private var selectedOverlay: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.52), Color.indigo.opacity(0.32), Color.white.opacity(0.56)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: Color.cyan.opacity(0.16), radius: 10, x: 0, y: 4)
        }
    }

    private var primaryMetric: String {
        if let image = previewImage {
            return "\(Int(image.size.width)) x \(Int(image.size.height))"
        }

        switch item.kind {
        case .text, .url:
            return "\(item.searchableText.count) 字符"
        case .file:
            return "文件"
        case .folder:
            return "文件夹"
        case .imageFile, .imageData:
            return "图片"
        case .unknown:
            return kindTitle
        }
    }

    private var relativeCreatedAt: String {
        let elapsed = max(0, Date().timeIntervalSince(item.createdAt))

        if elapsed < 60 {
            return "刚刚"
        }

        if elapsed < 3600 {
            return "\(Int(elapsed / 60)) 分钟前"
        }

        if elapsed < 86400 {
            return "\(Int(elapsed / 3600)) 小时前"
        }

        return "\(Int(elapsed / 86400)) 天前"
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
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.24), lineWidth: 1))
    }
}
