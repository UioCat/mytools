import AppKit
import SwiftUI

public struct ClipboardRowView: View {
    public let item: ClipboardItem
    public let index: Int
    public let isSelected: Bool
    public let showsBackground: Bool
    public let onFavoriteToggle: () -> Void
    @State private var isFavoriteButtonHovered = false

    public init(item: ClipboardItem) {
        self.item = item
        self.index = 1
        self.isSelected = false
        self.showsBackground = true
        self.onFavoriteToggle = {}
    }

    public init(
        item: ClipboardItem,
        index: Int = 1,
        isSelected: Bool,
        showsBackground: Bool = true,
        onFavoriteToggle: @escaping () -> Void
    ) {
        self.item = item
        self.index = index
        self.isSelected = isSelected
        self.showsBackground = showsBackground
        self.onFavoriteToggle = onFavoriteToggle
    }

    @ViewBuilder
    public var body: some View {
        if showsBackground {
            rowContent
                .liquidGlassModule(cornerRadius: 24, isSelected: isSelected)
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(item.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .lineLimit(isImage ? 1 : 2)

                Spacer(minLength: 12)

                if !isImage {
                    Text(primaryMetric)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.72))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("\(index)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.68))
                        .frame(width: 24, alignment: .trailing)

                    favoriteButton
                }
            }

            if isImage {
                imagePreview
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
            }

            HStack(spacing: 8) {
                Text(relativeCreatedAt)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.68))

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
                        .foregroundStyle(Color.black.opacity(0.72))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, isImage ? 16 : 14)
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
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.26), radius: 14, x: 0, y: 8)
        } else {
            Image(systemName: iconName)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.52))
        }
    }

    private var favoriteButton: some View {
        let presentation = ClipboardFavoriteButtonPresentation(
            isFavorite: item.isFavorite,
            isHovered: isFavoriteButtonHovered
        )

        return Button(action: onFavoriteToggle) {
            Image(systemName: presentation.iconName)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: presentation.hitSize.width, height: presentation.hitSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            item.isFavorite
                ? Color(nsColor: .controlAccentColor)
                : Color.black.opacity(presentation.foregroundOpacity)
        )
        .background(
            Circle()
                .fill(Color.white.opacity(presentation.backgroundOpacity))
        )
        .overlay(
            Circle()
                .strokeBorder(Color.black.opacity(presentation.strokeOpacity), lineWidth: 1)
        )
        .scaleEffect(presentation.scale)
        .onHover { isFavoriteButtonHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isFavoriteButtonHovered)
        .help(presentation.helpText)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
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

struct ClipboardFavoriteButtonPresentation: Equatable {
    let iconName: String
    let helpText: String
    let accessibilityLabel: String
    let foregroundOpacity: Double
    let backgroundOpacity: Double
    let strokeOpacity: Double
    let scale: CGFloat
    let hitSize: CGSize

    init(isFavorite: Bool, isHovered: Bool) {
        self.iconName = isFavorite ? "star.fill" : "star"
        self.helpText = isFavorite ? "取消收藏" : "加入收藏"
        self.accessibilityLabel = helpText
        self.foregroundOpacity = isFavorite ? 0.86 : (isHovered ? 0.76 : 0.48)
        self.backgroundOpacity = isHovered ? 0.40 : 0
        self.strokeOpacity = isHovered ? 0.18 : 0
        self.scale = isHovered ? 1.06 : 1
        self.hitSize = CGSize(width: 30, height: 30)
    }
}

private struct StatusLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.74))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .liquidGlassChip(cornerRadius: 9)
    }
}
