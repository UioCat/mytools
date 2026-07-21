import Foundation

public final class ClipboardClassifier {
    private let imageFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    public init() {}

    public func classify(payload: ClipboardPayload, sourceApp: String?) -> ClipboardItem {
        let now = Date()
        let contentHash = ClipboardContentHasher.sha256(for: payload)

        if let firstURL = payload.fileURLs.first {
            return classifyFileURL(firstURL, sourceApp: sourceApp, contentHash: contentHash, now: now)
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
                now: now
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
                now: now
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
            now: now
        )
    }

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
