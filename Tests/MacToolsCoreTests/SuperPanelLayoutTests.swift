import Foundation
import XCTest
@testable import MacToolsCore

final class SuperPanelLayoutTests: XCTestCase {
    private let tenLayoutButtons = (0..<10).map {
        WindowLayoutButton(id: "layout.\($0)", title: "布局 \($0)", modes: [.maximize])
    }

    func testTranslationPanelUsesExpandedWidthAndContentDrivenHeight() {
        let content = SuperPanelContent.text(
            originalText: "hello",
            translation: .success(
                TranslationResponse(translatedText: "你好", providerID: "test")
            )
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 420, height: 229)
        )
    }

    func testTranslationActionsUseStandardTextActionMetrics() {
        XCTAssertEqual(SuperPanelLayout.translationActionSectionHeight, 56)
        XCTAssertEqual(SuperPanelLayout.translationActionButtonHeight, 40)
        XCTAssertEqual(SuperPanelLayout.translationActionTitleFontSize, 14)
        XCTAssertEqual(SuperPanelLayout.translationActionSpacing, 8)
        XCTAssertEqual(SuperPanelLayout.translationActionSectionHorizontalPadding, 12)
        XCTAssertEqual(SuperPanelLayout.translationActionButtonHorizontalPadding, 16)
    }

    func testTextTransitPanelUsesExpandedContentDrivenSize() {
        let content = SuperPanelContent.textTransit(text: "brainstorming")

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 181)
        )
    }

    func testTranslationPanelHeightTracksRenderedTextLines() {
        let shortContent = SuperPanelContent.text(
            originalText: "short",
            translation: .success(
                TranslationResponse(translatedText: "简短", providerID: "test")
            )
        )
        let longContent = SuperPanelContent.text(
            originalText: String(repeating: "sample translation text ", count: 12),
            translation: .success(
                TranslationResponse(
                    translatedText: String(repeating: "示例译文", count: 24),
                    providerID: "test"
                )
            )
        )

        XCTAssertGreaterThan(
            SuperPanelLayout.panelSize(for: longContent).height,
            SuperPanelLayout.panelSize(for: shortContent).height
        )
        XCTAssertLessThanOrEqual(
            SuperPanelLayout.panelSize(for: longContent).height,
            620
        )
    }

    func testStandardLayoutPanelExpandsToFitTenButtons() {
        let content = SuperPanelContent.windowLayoutOnly(
            windowLayoutButtons: tenLayoutButtons
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 356)
        )
    }

    func testSelectedItemPanelExpandsToFitTenLayoutButtons() {
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: "Project",
            searchableText: "/tmp/Project",
            text: nil,
            originalPath: "/tmp/Project",
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "访达",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        let content = SuperPanelContent.fileSystem(
            item: item,
            windowLayoutButtons: tenLayoutButtons
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 460)
        )
    }

    func testFinderDirectoryPanelExpandsToFitActionsAndTenLayoutButtons() {
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: "Project",
            searchableText: "/tmp/Project",
            text: nil,
            originalPath: "/tmp/Project",
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "访达",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        let content = SuperPanelContent.fileSystem(
            item: item,
            windowLayoutButtons: tenLayoutButtons,
            presentation: .finderCurrentDirectory
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 574)
        )
    }

    func testFinderDirectoryPanelAccountsForWrappedPathPreview() {
        let longPath = "/Users/example/Projects/very-long-project-directory/with-nested-content"
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: "Project",
            searchableText: longPath,
            text: nil,
            originalPath: longPath,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "访达",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        let content = SuperPanelContent.fileSystem(
            item: item,
            windowLayoutButtons: tenLayoutButtons,
            presentation: .finderCurrentDirectory
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 591)
        )
    }

    func testFinderDirectoryPanelUsesRenderedWidthForWidePathCharacters() {
        let widePath = "/用户/项目/界面界面界面界面界面界面界面界面"
        let content = finderDirectoryContent(path: widePath)

        XCTAssertLessThan(widePath.count, 30)
        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 591)
        )
    }

    func testFinderDirectoryPanelDoesNotWrapNarrowPathByCharacterCount() {
        let narrowPath = "/" + String(repeating: "i", count: 35)
        let content = finderDirectoryContent(path: narrowPath)

        XCTAssertGreaterThan(narrowPath.count, 30)
        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 574)
        )
    }

    func testOversizedFolderPanelUsesExpandedMaximumHeight() {
        let twentyLayoutButtons = (0..<20).map {
            WindowLayoutButton(id: "layout.\($0)", title: "布局 \($0)", modes: [.maximize])
        }
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: "Project",
            searchableText: "/tmp/Project",
            text: nil,
            originalPath: "/tmp/Project",
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "访达",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        let content = SuperPanelContent.fileSystem(
            item: item,
            windowLayoutButtons: twentyLayoutButtons
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 620)
        )
    }

    func testHeaderUsesCompactMetrics() {
        XCTAssertEqual(SuperPanelLayout.headerIconSize, 36)
        XCTAssertEqual(SuperPanelLayout.headerTitleFontSize, 16)
        XCTAssertEqual(SuperPanelLayout.headerSubtitleFontSize, 11)
        XCTAssertEqual(SuperPanelLayout.headerTrailingIconFontSize, 18)
        XCTAssertEqual(SuperPanelLayout.headerHorizontalPadding, 14)
        XCTAssertEqual(SuperPanelLayout.headerTopPadding, 12)
        XCTAssertEqual(SuperPanelLayout.headerBottomPadding, 10)
    }

    private func finderDirectoryContent(path: String) -> SuperPanelContent {
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: "Project",
            searchableText: path,
            text: nil,
            originalPath: path,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "访达",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
        return SuperPanelContent.fileSystem(
            item: item,
            windowLayoutButtons: tenLayoutButtons,
            presentation: .finderCurrentDirectory
        )
    }
}
