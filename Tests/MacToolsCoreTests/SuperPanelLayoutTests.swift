import Foundation
import XCTest
@testable import MacToolsCore

final class SuperPanelLayoutTests: XCTestCase {
    private let eightLayoutButtons = (0..<8).map {
        WindowLayoutButton(id: "layout.\($0)", title: "布局 \($0)", modes: [.maximize])
    }

    func testTranslationPanelKeepsExpandedWidthAndUsesCompactActionHeight() {
        let content = SuperPanelContent.text(
            originalText: "hello",
            translation: .success(
                TranslationResponse(translatedText: "你好", providerID: "test")
            )
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 1_000.0 / 3.0, height: 196)
        )
    }

    func testTranslationActionsUseCompactReadableMetrics() {
        XCTAssertEqual(SuperPanelLayout.translationActionRowHeight, 44)
        XCTAssertEqual(SuperPanelLayout.translationActionIconSize, 28)
        XCTAssertEqual(SuperPanelLayout.translationActionIconFontSize, 14)
        XCTAssertEqual(SuperPanelLayout.translationActionTitleFontSize, 15)
        XCTAssertEqual(SuperPanelLayout.translationActionSpacing, 10)
        XCTAssertEqual(SuperPanelLayout.translationActionHorizontalPadding, 16)
        XCTAssertEqual(SuperPanelLayout.translationActionVerticalPadding, 8)
    }

    func testStandardLayoutPanelExpandsToFitEightButtons() {
        let content = SuperPanelContent.windowLayoutOnly(
            windowLayoutButtons: eightLayoutButtons
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 293)
        )
    }

    func testSelectedItemPanelExpandsToFitEightLayoutButtons() {
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
            windowLayoutButtons: eightLayoutButtons
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 399)
        )
    }

    func testFinderDirectoryPanelExpandsToFitActionsAndEightLayoutButtons() {
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
            windowLayoutButtons: eightLayoutButtons,
            presentation: .finderCurrentDirectory
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 515)
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
            windowLayoutButtons: eightLayoutButtons,
            presentation: .finderCurrentDirectory
        )

        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 532)
        )
    }

    func testFinderDirectoryPanelUsesRenderedWidthForWidePathCharacters() {
        let widePath = "/用户/项目/界面界面界面界面界面界面界面界面"
        let content = finderDirectoryContent(path: widePath)

        XCTAssertLessThan(widePath.count, 30)
        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 532)
        )
    }

    func testFinderDirectoryPanelDoesNotWrapNarrowPathByCharacterCount() {
        let narrowPath = "/" + String(repeating: "i", count: 35)
        let content = finderDirectoryContent(path: narrowPath)

        XCTAssertGreaterThan(narrowPath.count, 30)
        XCTAssertEqual(
            SuperPanelLayout.panelSize(for: content),
            CGSize(width: 320, height: 515)
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
            windowLayoutButtons: eightLayoutButtons,
            presentation: .finderCurrentDirectory
        )
    }
}
