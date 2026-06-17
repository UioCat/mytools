import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MacToolsCore

final class ClipboardListViewTests: XCTestCase {
    func testFavoriteButtonPresentationMakesHoverVisibleWithoutChangingHitSize() {
        let idle = ClipboardFavoriteButtonPresentation(isFavorite: false, isHovered: false)
        let hovered = ClipboardFavoriteButtonPresentation(isFavorite: false, isHovered: true)

        XCTAssertEqual(idle.iconName, "star")
        XCTAssertEqual(hovered.iconName, "star")
        XCTAssertEqual(idle.helpText, "加入收藏")
        XCTAssertEqual(idle.hitSize, hovered.hitSize)
        XCTAssertGreaterThan(hovered.backgroundOpacity, idle.backgroundOpacity)
        XCTAssertGreaterThan(hovered.strokeOpacity, idle.strokeOpacity)
        XCTAssertGreaterThan(hovered.foregroundOpacity, idle.foregroundOpacity)
        XCTAssertGreaterThan(hovered.scale, idle.scale)
    }

    func testFavoriteButtonPresentationUsesFilledStarForFavoriteItems() {
        let presentation = ClipboardFavoriteButtonPresentation(isFavorite: true, isHovered: false)

        XCTAssertEqual(presentation.iconName, "star.fill")
        XCTAssertEqual(presentation.helpText, "取消收藏")
        XCTAssertEqual(presentation.accessibilityLabel, "取消收藏")
    }

    func testClipboardPanelItemSummaryCountsFavoritesAndClearableItems() {
        let summary = ClipboardPanelItemSummary(items: [
            makeItem(isFavorite: true),
            makeItem(isFavorite: false),
            makeItem(isFavorite: true)
        ])

        XCTAssertEqual(summary.favoriteCount, 2)
        XCTAssertTrue(summary.hasClearableItems)
        XCTAssertFalse(ClipboardPanelItemSummary(items: [makeItem(isFavorite: true)]).hasClearableItems)
    }

    func testClipboardPanelRenderStateFiltersAndSelectsItemsInOnePassModel() {
        let textItem = makeItem(text: "release notes")
        let searchableOnlyItem = makeItem(
            text: "daily log",
            displayTitle: "Daily",
            searchableText: "hidden release detail"
        )
        let favoriteItem = makeItem(text: "pinned design", isFavorite: true)
        let folderItem = makeItem(kind: .folder, text: "Projects")
        let imageItem = makeImageItem(originalPath: "/tmp/screen.png")

        let items = [textItem, searchableOnlyItem, favoriteItem, folderItem, imageItem]

        let allState = ClipboardPanelRenderState(
            items: items,
            mode: .all,
            query: "",
            selectedItemID: nil
        )
        XCTAssertEqual(allState.filteredItems.map(\.id), items.map(\.id))
        XCTAssertEqual(allState.selectedItem?.id, textItem.id)

        let textState = ClipboardPanelRenderState(
            items: items,
            mode: .text,
            query: "  Release  ",
            selectedItemID: favoriteItem.id
        )
        XCTAssertEqual(textState.filteredItems.map(\.id), [textItem.id, searchableOnlyItem.id])
        XCTAssertEqual(textState.selectedItem?.id, textItem.id)
        XCTAssertEqual(textState.itemSummary.favoriteCount, 1)

        let imageState = ClipboardPanelRenderState(
            items: items,
            mode: .images,
            query: "",
            selectedItemID: nil
        )
        XCTAssertEqual(imageState.filteredItems.map(\.id), [imageItem.id])

        let folderState = ClipboardPanelRenderState(
            items: items,
            mode: .folders,
            query: "",
            selectedItemID: nil
        )
        XCTAssertEqual(folderState.filteredItems.map(\.id), [folderItem.id])

        let favoriteState = ClipboardPanelRenderState(
            items: items,
            mode: .favorites,
            query: "",
            selectedItemID: favoriteItem.id
        )
        XCTAssertEqual(favoriteState.filteredItems.map(\.id), [favoriteItem.id])
        XCTAssertEqual(favoriteState.selectedItem?.id, favoriteItem.id)

        let emptyState = ClipboardPanelRenderState(
            items: items,
            mode: .all,
            query: "not-found",
            selectedItemID: textItem.id
        )
        XCTAssertTrue(emptyState.filteredItems.isEmpty)
        XCTAssertNil(emptyState.selectedItem)
    }

    func testImagePreviewCacheConfigurationKeepsMemoryBounded() {
        XCTAssertEqual(ClipboardImagePreviewCache.Configuration.standard.countLimit, 120)
        XCTAssertEqual(
            ClipboardImagePreviewCache.Configuration.standard.totalCostLimit,
            128 * 1024 * 1024
        )
    }

    func testImagePreviewSourceCacheKeyTracksFileChanges() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("preview.png")
        try Data([1]).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: fileURL.path
        )
        let firstKey = try XCTUnwrap(
            ClipboardImagePreviewSource.source(for: makeImageItem(originalPath: fileURL.path))?.cacheKey
        )

        try Data([1, 2, 3, 4]).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 20)],
            ofItemAtPath: fileURL.path
        )
        let updatedKey = try XCTUnwrap(
            ClipboardImagePreviewSource.source(for: makeImageItem(originalPath: fileURL.path))?.cacheKey
        )

        XCTAssertNotEqual(firstKey, updatedKey)
        XCTAssertTrue(updatedKey.contains(fileURL.path))
    }

    func testImagePreviewSourceCacheKeyIncludesContentHash() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("preview.png")
        try Data([1, 2, 3, 4]).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 10)],
            ofItemAtPath: fileURL.path
        )

        let firstKey = try XCTUnwrap(
            ClipboardImagePreviewSource.source(
                for: makeImageItem(originalPath: fileURL.path, contentHash: "first")
            )?.cacheKey
        )
        let updatedKey = try XCTUnwrap(
            ClipboardImagePreviewSource.source(
                for: makeImageItem(originalPath: fileURL.path, contentHash: "second")
            )?.cacheKey
        )

        XCTAssertNotEqual(firstKey, updatedKey)
        XCTAssertTrue(firstKey.contains("hash:first"))
        XCTAssertTrue(updatedKey.contains("hash:second"))
    }

    func testImagePreviewCacheLoadsImageIOThumbnailAndMetric() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("preview.png")
        try writeTestPNG(to: fileURL, width: 2, height: 3)

        let source = try XCTUnwrap(
            ClipboardImagePreviewSource.source(for: makeImageItem(originalPath: fileURL.path))
        )
        let cache = ClipboardImagePreviewCache(
            configuration: .init(countLimit: 2, totalCostLimit: 2 * 1024 * 1024)
        )
        let preview = try XCTUnwrap(cache.preview(for: source))

        XCTAssertEqual(preview.metric, "2 x 3")
        XCTAssertEqual(preview.cgImage.width, 2)
        XCTAssertEqual(preview.cgImage.height, 3)
    }

    func testScrollAnchorKeepsFirstSelectionAtTop() {
        let items = [makeItem(), makeItem(), makeItem()]

        XCTAssertEqual(
            ClipboardListScrollAnchorPolicy.anchor(for: items[0].id, in: items),
            .top
        )
        XCTAssertEqual(
            ClipboardListScrollAnchorPolicy.anchor(for: items[1].id, in: items),
            .center
        )
        XCTAssertEqual(
            ClipboardListScrollAnchorPolicy.anchor(for: items[2].id, in: items),
            .bottom
        )
    }

    func testScrollAnchorFallsBackToCenterForMissingSelection() {
        XCTAssertEqual(
            ClipboardListScrollAnchorPolicy.anchor(for: UUID(), in: [makeItem()]),
            .center
        )
    }

    func testImagePreviewSourcePrefersThumbnailThenCachedFileThenOriginalPath() {
        XCTAssertEqual(
            ClipboardImagePreviewSource.source(
                for: makeImageItem(
                    thumbnailPath: "/tmp/thumb.png",
                    cachedFilePath: "/tmp/cache.png",
                    originalPath: "/tmp/original.png"
                )
            )?.path,
            "/tmp/thumb.png"
        )
        XCTAssertEqual(
            ClipboardImagePreviewSource.source(
                for: makeImageItem(cachedFilePath: "/tmp/cache.png", originalPath: "/tmp/original.png")
            )?.path,
            "/tmp/cache.png"
        )
        XCTAssertEqual(
            ClipboardImagePreviewSource.source(
                for: makeImageItem(originalPath: "/tmp/original.png")
            )?.path,
            "/tmp/original.png"
        )
    }

    func testImagePreviewSourceIgnoresNonImagesAndMissingPaths() {
        XCTAssertNil(ClipboardImagePreviewSource.source(for: makeItem()))
        XCTAssertNil(ClipboardImagePreviewSource.source(for: makeImageItem()))
    }

    private func makeItem(
        id: UUID = UUID(),
        kind: ClipboardContentKind = .text,
        text: String = "Snippet",
        displayTitle: String? = nil,
        searchableText: String? = nil,
        isFavorite: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            displayTitle: displayTitle ?? text,
            searchableText: searchableText ?? text,
            text: kind == .text || kind == .url ? text : nil,
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "MacTools",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: isFavorite
        )
    }

    private func makeImageItem(
        id: UUID = UUID(),
        kind: ClipboardContentKind = .imageData,
        displayTitle: String = "Image",
        searchableText: String = "Image",
        thumbnailPath: String? = nil,
        cachedFilePath: String? = nil,
        originalPath: String? = nil,
        contentHash: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            displayTitle: displayTitle,
            searchableText: searchableText,
            text: nil,
            originalPath: originalPath,
            cachedFilePath: cachedFilePath,
            thumbnailPath: thumbnailPath,
            sourceApp: "Preview",
            contentHash: contentHash,
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeTestPNG(to url: URL, width: Int, height: Int) throws {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }

        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw TestImageError.imageCreationFailed
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.imageCreationFailed
        }
    }

    private enum TestImageError: Error {
        case contextCreationFailed
        case imageCreationFailed
    }
}
