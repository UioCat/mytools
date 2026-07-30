import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import MacToolsCore

private final class LockedThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) {
        lock.withLock { values.append(value) }
    }

    var snapshot: [Bool] {
        lock.withLock { values }
    }
}

final class ClipboardListViewTests: XCTestCase {
    func testClipboardCategoriesContainOnlyRequestedModes() {
        XCTAssertEqual(ClipboardPanelMode.allCases, [.all, .text, .images, .favorites])
        XCTAssertEqual(ClipboardPanelMode.allCases.map(\.title), ["全部", "文本", "图像", "收藏"])
    }

    func testClipboardCategoryArrowNavigationMovesBetweenAdjacentModes() {
        XCTAssertEqual(
            ClipboardPanelModeNavigator.mode(adjacentTo: .all, direction: .next),
            .text
        )
        XCTAssertEqual(
            ClipboardPanelModeNavigator.mode(adjacentTo: .text, direction: .next),
            .images
        )
        XCTAssertEqual(
            ClipboardPanelModeNavigator.mode(adjacentTo: .favorites, direction: .previous),
            .images
        )
    }

    func testClipboardCategoryArrowNavigationWrapsAtFirstAndLastModes() {
        XCTAssertEqual(
            ClipboardPanelModeNavigator.mode(adjacentTo: .all, direction: .previous),
            .favorites
        )
        XCTAssertEqual(
            ClipboardPanelModeNavigator.mode(adjacentTo: .favorites, direction: .next),
            .all
        )
    }

    func testClipboardCategoryArrowKeyCodesResolveToNavigationDirections() {
        XCTAssertEqual(ClipboardPanelModeNavigator.direction(forKeyCode: 123), .previous)
        XCTAssertEqual(ClipboardPanelModeNavigator.direction(forKeyCode: 124), .next)
        XCTAssertNil(ClipboardPanelModeNavigator.direction(forKeyCode: 125))
        XCTAssertNil(ClipboardPanelModeNavigator.direction(forKeyCode: 126))
    }

    func testFirstMouseClickSelectsAndSecondClickOnSameItemPastes() {
        let itemID = UUID()

        XCTAssertEqual(
            ClipboardItemClickResolver.action(
                clickedItemID: itemID,
                selectedItemID: itemID,
                armedItemID: nil
            ),
            .select
        )
        XCTAssertEqual(
            ClipboardItemClickResolver.action(
                clickedItemID: itemID,
                selectedItemID: itemID,
                armedItemID: itemID
            ),
            .paste
        )
    }

    func testClickingDifferentItemStartsASelectionBeforePaste() {
        let selectedItemID = UUID()
        let clickedItemID = UUID()

        XCTAssertEqual(
            ClipboardItemClickResolver.action(
                clickedItemID: clickedItemID,
                selectedItemID: selectedItemID,
                armedItemID: selectedItemID
            ),
            .select
        )
    }

    func testImageRowsUseExpandedPreviewInsteadOfStandardTitleLayout() {
        XCTAssertEqual(ClipboardRowContentStyle.style(for: .imageData), .expandedImagePreview)
        XCTAssertEqual(ClipboardRowContentStyle.style(for: .imageFile), .expandedImagePreview)
        XCTAssertEqual(ClipboardRowContentStyle.style(for: .text), .standard)
        XCTAssertEqual(ClipboardRowContentStyle.style(for: .file), .standard)
    }

    func testClipboardTextUsesReadableTwelvePointFontAndAtMostThreeLines() {
        XCTAssertEqual(ClipboardRowTextPresentation.fontSize, 12, accuracy: 0.001)
        XCTAssertEqual(ClipboardRowTextPresentation.lineLimit, 3)
    }

    @MainActor
    func testWriteClipboardRowSnapshotsWhenRequested() throws {
        guard let outputDirectoryPath = ProcessInfo.processInfo.environment["MACTOOLS_CLIPBOARD_SNAPSHOT_DIR"] else {
            return
        }

        let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let item = makeItem(
            text: "第一行：这是用于验证剪贴板展示的较长内容。\n第二行：正文使用更易读的十二点字号。\n第三行：这是允许展示的最后一行。\n第四行：这一行应该被截断。\n第五行：不应继续展示。"
        )

        try writeClipboardRowSnapshot(
            item: item,
            colorScheme: .light,
            background: Color(white: 0.92),
            to: outputDirectory.appendingPathComponent("clipboard-row-light.png")
        )
        try writeClipboardRowSnapshot(
            item: item,
            colorScheme: .dark,
            background: Color(white: 0.08),
            to: outputDirectory.appendingPathComponent("clipboard-row-dark.png")
        )
    }

    func testRowMetadataSeparatesPasteTimeFromTextCharacterCount() {
        let item = makeItem(text: "当前剪切板的信息")
        let now = item.createdAt.addingTimeInterval(12 * 60)

        let metadata = ClipboardRowMetadataPresentation(item: item, now: now)

        XCTAssertEqual(metadata.pasteTime, "12 分钟前")
        XCTAssertEqual(metadata.contentSummary, "8 字符")
    }

    func testRowMetadataUsesLoadedImageDimensionsAsContentSummary() {
        let item = makeImageItem()

        let metadata = ClipboardRowMetadataPresentation(
            item: item,
            imageMetric: "1280 x 934",
            now: item.createdAt.addingTimeInterval(30 * 60)
        )

        XCTAssertEqual(metadata.pasteTime, "30 分钟前")
        XCTAssertEqual(metadata.contentSummary, "1280 x 934")
    }

    func testFavoriteButtonPresentationMakesHoverVisibleWithoutChangingHitSize() {
        let idle = ClipboardFavoriteButtonPresentation(isFavorite: false, isHovered: false)
        let hovered = ClipboardFavoriteButtonPresentation(isFavorite: false, isHovered: true)

        XCTAssertEqual(idle.iconName, "star")
        XCTAssertEqual(hovered.iconName, "star")
        XCTAssertEqual(idle.helpText, "加入收藏")
        XCTAssertEqual(idle.hitSize, CGSize(width: 32, height: 32))
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

    func testImagePreviewCacheLoadsImageIOThumbnailAndMetric() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("preview.png")
        try writeTestPNG(to: fileURL, width: 2, height: 3)

        let source = ClipboardImagePreviewSource.resolve(
            .init(path: fileURL.path, contentHash: nil),
            attributes: .init(byteCount: 64, modificationDate: nil)
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

    func testImagePreviewRequestSelectsPathWithoutResolvingFileAttributes() throws {
        let request = try XCTUnwrap(
            ClipboardImagePreviewRequest.request(
                for: makeImageItem(
                    thumbnailPath: "/not-mounted/thumb.png",
                    cachedFilePath: "/cache/image.png",
                    originalPath: "/original/image.png",
                    contentHash: "  abc123  "
                )
            )
        )

        XCTAssertEqual(request.path, "/not-mounted/thumb.png")
        XCTAssertEqual(request.contentHash, "abc123")
    }

    @MainActor
    func testImagePreviewLoaderResolvesAndDecodesOffMainThread() async throws {
        let observations = LockedThreadObservation()
        let request = ClipboardImagePreviewRequest(
            path: "/virtual/image.png",
            contentHash: "hash"
        )
        let loader = ClipboardImagePreviewLoader(
            attributesProvider: { _ in
                observations.append(Thread.isMainThread)
                return .init(
                    byteCount: 4,
                    modificationDate: Date(timeIntervalSinceReferenceDate: 10)
                )
            },
            previewProvider: { _ in
                observations.append(Thread.isMainThread)
                return nil
            }
        )

        _ = await loader.load(request)

        XCTAssertEqual(observations.snapshot, [false, false])
    }

    func testResolvedImagePreviewCacheKeyTracksAttributesAndContentHash() {
        let request = ClipboardImagePreviewRequest(
            path: "/cache/image.png",
            contentHash: "first"
        )
        let first = ClipboardImagePreviewSource.resolve(
            request,
            attributes: .init(
                byteCount: 1,
                modificationDate: Date(timeIntervalSinceReferenceDate: 10)
            )
        )
        let changed = ClipboardImagePreviewSource.resolve(
            .init(path: request.path, contentHash: "second"),
            attributes: .init(
                byteCount: 4,
                modificationDate: Date(timeIntervalSinceReferenceDate: 20)
            )
        )

        XCTAssertEqual(
            first.cacheKey,
            "/cache/image.png|size:1|modified:10.0|hash:first"
        )
        XCTAssertNotEqual(first.cacheKey, changed.cacheKey)
    }

    @MainActor
    func testCancelledImagePreviewLoadDoesNotReturnDecodedPreview() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("preview.png")
        try writeTestPNG(to: fileURL, width: 2, height: 3)
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let cache = ClipboardImagePreviewCache(
            configuration: .init(countLimit: 1, totalCostLimit: 1_024 * 1_024)
        )
        let loader = ClipboardImagePreviewLoader(
            attributesProvider: { _ in
                .init(
                    byteCount: 64,
                    modificationDate: Date(timeIntervalSinceReferenceDate: 10)
                )
            },
            previewProvider: { source in
                started.signal()
                release.wait()
                return cache.preview(for: source)
            }
        )
        let task = Task {
            await loader.load(.init(path: fileURL.path, contentHash: "hash"))
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                started.wait()
                continuation.resume()
            }
        }

        task.cancel()
        release.signal()

        let preview = await task.value
        XCTAssertNil(preview)
    }

    func testImagePreviewSourceIgnoresNonImagesAndMissingPaths() {
        XCTAssertNil(ClipboardImagePreviewRequest.request(for: makeItem()))
        XCTAssertNil(ClipboardImagePreviewRequest.request(for: makeImageItem()))
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

    @MainActor
    private func writeClipboardRowSnapshot(
        item: ClipboardItem,
        colorScheme: ColorScheme,
        background: Color,
        to url: URL
    ) throws {
        let renderedSize = CGSize(width: 720, height: 160)
        let renderer = ImageRenderer(
            content: ClipboardRowView(
                item: item,
                index: 1,
                isSelected: true,
                showsBackground: false,
                onFavoriteToggle: {}
            )
            .frame(width: 680)
            .padding(20)
            .background(background)
            .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(
            width: renderedSize.width,
            height: nil
        )

        guard let image = renderer.nsImage,
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not render clipboard row snapshot: \(url.path)")
            return
        }

        try pngData.write(to: url)
        XCTAssertEqual(bitmap.pixelsWide, Int(renderedSize.width * renderer.scale))
        XCTAssertGreaterThan(bitmap.pixelsHigh, 180)
        XCTAssertLessThan(bitmap.pixelsHigh, Int(renderedSize.height * renderer.scale))
        XCTAssertGreaterThan(pngData.count, 1_000)
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
