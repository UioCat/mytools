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

    private func makeItem(id: UUID = UUID()) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .text,
            displayTitle: "Snippet",
            searchableText: "Snippet",
            text: "Snippet",
            originalPath: nil,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "MacTools",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }
}
