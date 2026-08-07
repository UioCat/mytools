// `ClipboardClassifier` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import Foundation

/// 管理 `ClipboardClassifier` 在剪贴板领域中的生命周期、依赖和可变状态。
public final class ClipboardClassifier {
    private let imageFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    /// 创建 `ClipboardClassifier`，保存传入依赖并建立初始状态。
    public init() {}

    /// 根据输入特征判定 `classify` 对应的剪贴板领域分类或处理决策。
    public func classify(
        payload: ClipboardPayload,
        sourceApp: String?,
        capturedAt: Date = Date()
    ) -> ClipboardItem {
        let contentHash = ClipboardContentHasher.sha256(for: payload)

        if let firstURL = payload.fileURLs.first {
            return classifyFileURL(
                firstURL,
                sourceApp: sourceApp,
                contentHash: contentHash,
                now: capturedAt
            )
        }

        if let text = payload.text, !text.isEmpty {
            let kind: ClipboardContentKind = URL(string: text)?.scheme == nil ? .text : .url
            return makeItem(
                kind: kind,
                displayTitle: String(text.prefix(80)),
                searchableText: text,
                text: text,
                originalPath: nil,
                sourceApp: sourceApp,
                contentHash: contentHash,
                now: capturedAt
            )
        }

        if let imageData = payload.imageData, !imageData.isEmpty {
            let title = sourceApp.map { "Image from \($0)" } ?? "Image from Clipboard"
            return makeItem(
                kind: .imageData,
                displayTitle: title,
                searchableText: sourceApp ?? "image",
                text: nil,
                originalPath: nil,
                sourceApp: sourceApp,
                contentHash: contentHash,
                now: capturedAt
            )
        }

        return makeItem(
            kind: .unknown,
            displayTitle: "Unknown clipboard item",
            searchableText: sourceApp ?? "",
            text: nil,
            originalPath: nil,
            sourceApp: sourceApp,
            contentHash: contentHash,
            now: capturedAt
        )
    }

    /// 根据输入特征判定 `classifyFileURL` 对应的剪贴板领域分类或处理决策。
    private func classifyFileURL(
        _ url: URL,
        sourceApp: String?,
        contentHash: String?,
        now: Date
    ) -> ClipboardItem {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isImageFile = imageFileExtensions.contains(url.pathExtension.lowercased())
        let kind: ClipboardContentKind

        if isDirectory {
            kind = .folder
        } else if isImageFile {
            kind = .imageFile
        } else {
            kind = .file
        }

        return makeItem(
            kind: kind,
            displayTitle: url.lastPathComponent,
            searchableText: url.path,
            text: nil,
            originalPath: url.path,
            sourceApp: sourceApp,
            contentHash: contentHash,
            now: now
        )
    }

    /// 构造并返回 `makeItem` 所描述的剪贴板领域对象。
    private func makeItem(
        kind: ClipboardContentKind,
        displayTitle: String,
        searchableText: String,
        text: String?,
        originalPath: String?,
        sourceApp: String?,
        contentHash: String?,
        now: Date
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: displayTitle,
            searchableText: searchableText,
            text: text,
            originalPath: originalPath,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: sourceApp,
            contentHash: contentHash,
            createdAt: now,
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }
}
