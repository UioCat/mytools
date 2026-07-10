import AppKit
import ImageIO
import SwiftUI

public struct ClipboardRowView: View {
    public let item: ClipboardItem
    public let index: Int
    public let isSelected: Bool
    public let showsBackground: Bool
    public let onFavoriteToggle: () -> Void
    @State private var isFavoriteButtonHovered = false
    @State private var loadedImagePreview: ClipboardLoadedImagePreview?

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
                .liquidGlassConcentricModule(isSelected: isSelected)
        } else {
            rowContent
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        let metadata = ClipboardRowMetadataPresentation(
            item: item,
            imageMetric: currentImagePreview?.metric
        )

        if ClipboardRowContentStyle.style(for: item.kind) == .expandedImagePreview {
            imageRowContent(metadata: metadata)
                .task(id: imagePreviewSource) {
                    await loadImagePreview()
                }
        } else {
            standardRowContent(metadata: metadata)
        }
    }

    private func standardRowContent(metadata: ClipboardRowMetadataPresentation) -> some View {
        HStack(spacing: 14) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)

                Text(metadata.pasteTime)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(index)")
                    .font(.system(size: 12, weight: .semibold))

                Text(metadata.contentSummary)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(MacToolsGlassTheme.textTertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)

            favoriteButton
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func imageRowContent(metadata: ClipboardRowMetadataPresentation) -> some View {
        VStack(spacing: 10) {
            Group {
                if let preview = currentImagePreview {
                    Image(decorative: preview.cgImage, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 440, maxHeight: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(MacToolsGlassTheme.border, lineWidth: 0.5)
                        )
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 36, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(MacToolsGlassTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("剪贴板图片"))
            .accessibilityValue(Text(metadata.contentSummary))

            HStack(spacing: 14) {
                Text(metadata.pasteTime)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(index)")
                        .font(.system(size: 12, weight: .semibold))

                    Text(metadata.contentSummary)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                }
                .foregroundStyle(MacToolsGlassTheme.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                favoriteButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if let preview = currentImagePreview {
            Image(decorative: preview.cgImage, scale: 1, orientation: .up)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(MacToolsGlassTheme.border, lineWidth: 0.5)
                )
        } else {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? MacToolsGlassTheme.textPrimary : MacToolsGlassTheme.textSecondary)
                .frame(width: 44, height: 44)
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
                ? Color.yellow.opacity(0.95)
                : Color.secondary.opacity(presentation.foregroundOpacity)
        )
        .background(
            Circle()
                .fill(Color.primary.opacity(presentation.backgroundOpacity * 0.14))
        )
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(presentation.strokeOpacity * 0.24), lineWidth: 0.5)
        )
        .scaleEffect(presentation.scale)
        .onHover { isFavoriteButtonHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isFavoriteButtonHovered)
        .help(presentation.helpText)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private var imagePreviewSource: ClipboardImagePreviewSource? {
        ClipboardImagePreviewSource.source(for: item)
    }

    private var currentImagePreview: ClipboardLoadedImagePreview? {
        guard let imagePreviewSource,
              loadedImagePreview?.source == imagePreviewSource else {
            return nil
        }

        return loadedImagePreview
    }

    private func loadImagePreview() async {
        guard let imagePreviewSource else {
            loadedImagePreview = nil
            return
        }

        guard loadedImagePreview?.source != imagePreviewSource else {
            return
        }

        let decodeTask = Task.detached(priority: .utility) { () -> ClipboardLoadedImagePreview? in
            guard !Task.isCancelled else {
                return nil
            }

            return ClipboardImagePreviewCache.shared.preview(for: imagePreviewSource)
        }
        let preview = await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }

        guard !Task.isCancelled,
              self.imagePreviewSource == imagePreviewSource else {
            return
        }

        loadedImagePreview = preview
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

}

enum ClipboardRowContentStyle: Equatable {
    case standard
    case expandedImagePreview

    static func style(for kind: ClipboardContentKind) -> ClipboardRowContentStyle {
        switch kind {
        case .imageFile, .imageData:
            return .expandedImagePreview
        case .text, .url, .file, .folder, .unknown:
            return .standard
        }
    }
}

struct ClipboardRowMetadataPresentation: Equatable {
    let pasteTime: String
    let contentSummary: String

    init(
        item: ClipboardItem,
        imageMetric: String? = nil,
        now: Date = Date()
    ) {
        self.pasteTime = Self.relativeTime(from: item.createdAt, to: now)

        if let imageMetric {
            self.contentSummary = imageMetric
        } else {
            switch item.kind {
            case .text, .url:
                self.contentSummary = "\(item.searchableText.count) 字符"
            case .file:
                self.contentSummary = "文件"
            case .folder:
                self.contentSummary = "文件夹"
            case .imageFile, .imageData:
                self.contentSummary = "图片"
            case .unknown:
                self.contentSummary = "内容"
            }
        }
    }

    private static func relativeTime(from createdAt: Date, to now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(createdAt))

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
}

struct ClipboardImagePreviewSource: Equatable, Hashable, Sendable {
    let path: String
    let cacheKey: String

    init(path: String, cacheKey: String? = nil) {
        self.path = path
        self.cacheKey = cacheKey ?? path
    }

    static func source(for item: ClipboardItem) -> ClipboardImagePreviewSource? {
        guard item.kind == .imageData || item.kind == .imageFile else {
            return nil
        }

        guard let path = [item.thumbnailPath, item.cachedFilePath, item.originalPath]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        return ClipboardImagePreviewSource(path: path, cacheKey: cacheKey(forPath: path, contentHash: item.contentHash))
    }

    static func cacheKey(forPath path: String, contentHash: String? = nil) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return [path, normalizedContentHash(contentHash)]
                .compactMap(\.self)
                .joined(separator: "|")
        }

        let fileSize = attributes[.size] as? NSNumber
        let modificationDate = attributes[.modificationDate] as? Date
        return [
            path,
            fileSize.map { "size:\($0.int64Value)" },
            modificationDate.map { "modified:\($0.timeIntervalSinceReferenceDate)" },
            normalizedContentHash(contentHash)
        ]
        .compactMap(\.self)
        .joined(separator: "|")
    }

    private static func normalizedContentHash(_ contentHash: String?) -> String? {
        guard let hash = contentHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hash.isEmpty else {
            return nil
        }

        return "hash:\(hash)"
    }
}

struct ClipboardLoadedImagePreview: @unchecked Sendable {
    let source: ClipboardImagePreviewSource
    let cgImage: CGImage
    let pixelWidth: Int
    let pixelHeight: Int

    var metric: String {
        "\(pixelWidth) x \(pixelHeight)"
    }

    var byteCost: Int {
        cgImage.bytesPerRow * cgImage.height
    }
}

final class ClipboardImagePreviewCache: @unchecked Sendable {
    struct Configuration: Equatable {
        let countLimit: Int
        let totalCostLimit: Int

        static let standard = Configuration(
            countLimit: 120,
            totalCostLimit: 128 * 1024 * 1024
        )
    }

    static let shared = ClipboardImagePreviewCache()

    private let cache = NSCache<NSString, ClipboardLoadedImagePreviewBox>()

    init(configuration: Configuration = .standard) {
        cache.countLimit = configuration.countLimit
        cache.totalCostLimit = configuration.totalCostLimit
    }

    func preview(for source: ClipboardImagePreviewSource) -> ClipboardLoadedImagePreview? {
        let key = NSString(string: source.cacheKey)
        if let cached = cache.object(forKey: key)?.preview {
            return cached
        }

        guard let preview = Self.loadPreview(for: source) else {
            return nil
        }

        cache.setObject(
            ClipboardLoadedImagePreviewBox(preview),
            forKey: key,
            cost: preview.byteCost
        )
        return preview
    }

    private static func loadPreview(for source: ClipboardImagePreviewSource) -> ClipboardLoadedImagePreview? {
        let url = URL(fileURLWithPath: source.path)
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 720
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
            return nil
        }

        return ClipboardLoadedImagePreview(
            source: source,
            cgImage: cgImage,
            pixelWidth: properties?[kCGImagePropertyPixelWidth] as? Int ?? cgImage.width,
            pixelHeight: properties?[kCGImagePropertyPixelHeight] as? Int ?? cgImage.height
        )
    }
}

private final class ClipboardLoadedImagePreviewBox {
    let preview: ClipboardLoadedImagePreview

    init(_ preview: ClipboardLoadedImagePreview) {
        self.preview = preview
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
