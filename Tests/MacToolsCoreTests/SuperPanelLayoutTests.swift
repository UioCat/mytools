import Foundation
import XCTest
@testable import MacToolsCore

final class SuperPanelLayoutTests: XCTestCase {
    func testTextPanelUsesHalfWidthAndHalfDynamicHeight() {
        let content = SuperPanelContent.text(
            originalText: "hello",
            translation: .success(
                TranslationResponse(translatedText: "你好", providerID: "test")
            )
        )

        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).width, 250)
        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 161)
    }

    func testEmptyLayoutPanelUsesHalfMinimumHeight() {
        let content = SuperPanelContent.windowLayoutOnly(windowLayoutButtons: [])

        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 130)
    }

    func testLargeFolderPanelUsesHalfMaximumHeight() {
        let buttons = (0..<8).map {
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
            windowLayoutButtons: buttons
        )

        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).width, 260)
        XCTAssertEqual(SuperPanelLayout.panelSize(for: content).height, 310)
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
}
