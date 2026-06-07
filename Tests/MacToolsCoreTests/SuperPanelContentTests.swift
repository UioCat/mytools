import Foundation
import XCTest
@testable import MacToolsCore

final class SuperPanelContentTests: XCTestCase {
    func testTextPanelSummarizesSelectionAndPrioritizesTranslationActions() {
        let content = SuperPanelContent.text(
            originalText: "super right click",
            translation: .success(
                TranslationResponse(translatedText: "超级右键点击", providerID: "bailian")
            )
        )

        XCTAssertEqual(content.kind, .text)
        XCTAssertEqual(content.headerTitle, "选中的文本 17 个")
        XCTAssertEqual(content.headerSubtitle, "超级右键点击")
        XCTAssertEqual(content.previewRows, [
            .init(label: "原文", value: "super right click"),
            .init(label: "译文", value: "超级右键点击")
        ])
        XCTAssertEqual(
            content.actions.map(\.id),
            [.copyTranslatedText, .textTransit]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["复制译文", "文本悬浮中转"]
        )
    }

    func testTextPanelStillOffersTransitWhenTranslationIsNotConfigured() {
        let content = SuperPanelContent.text(
            originalText: "hello",
            translation: .failure(.providerNotConfigured),
            windowLayoutButtons: [
                WindowLayoutButton(id: "custom.left-right", title: "左右半屏", modes: [.leftHalf, .rightHalf])
            ]
        )

        XCTAssertEqual(content.headerTitle, "选中的文本 5 个")
        XCTAssertEqual(content.headerSubtitle, "翻译未配置")
        XCTAssertEqual(content.previewRows, [
            .init(label: "原文", value: "hello"),
            .init(label: "提示", value: "在设置里填写 DASHSCOPE_API_KEY 后可显示翻译结果")
        ])
        XCTAssertEqual(
            content.actions.map(\.id),
            [.textTransit, .windowLayoutButton("custom.left-right")]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["文本悬浮中转", "左右半屏"]
        )
    }

    func testTextTransitPanelShowsSelectedTextAndCopyAction() {
        let content = SuperPanelContent.textTransit(text: " replacing existing signature ")

        XCTAssertEqual(content.kind, .textTransit)
        XCTAssertEqual(content.headerTitle, "文本悬浮中转")
        XCTAssertEqual(content.headerSubtitle, "28 个字符")
        XCTAssertEqual(content.previewRows, [
            .init(label: "文本", value: "replacing existing signature")
        ])
        XCTAssertEqual(content.actions.map(\.id), [.copyTransitText])
        XCTAssertEqual(content.actions.map(\.title), ["复制文本"])
    }

    func testFolderPanelUsesFinderStyleHeaderAndFileActions() {
        let content = SuperPanelContent.fileSystem(
            item: .testItem(
                kind: .folder,
                displayTitle: "linux-6.10",
                originalPath: "/Users/example/Downloads/linux-6.10",
                sourceApp: "访达"
            )
        )

        XCTAssertEqual(content.kind, .fileSystem)
        XCTAssertEqual(content.headerTitle, "访达")
        XCTAssertEqual(content.headerSubtitle, "linux-6.10")
        XCTAssertEqual(content.previewRows, [
            .init(label: "文件夹", value: "/Users/example/Downloads/linux-6.10")
        ])
        XCTAssertEqual(
            content.actions.map(\.id),
            [.copyPath, .createNewFile, .openTerminal, .openClaudeCode, .openClaudeCodeSkipConfirmation]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["复制当前路径", "新建文件", "终端中打开", "Claude Code 打开", "Claude Code 打开（跳过确认）"]
        )
    }

    func testFilePanelKeepsPathActionAndRevealFallback() {
        let content = SuperPanelContent.fileSystem(
            item: .testItem(
                kind: .file,
                displayTitle: "notes.md",
                originalPath: "/Users/example/notes.md",
                sourceApp: "访达"
            )
        )

        XCTAssertEqual(content.previewRows, [
            .init(label: "文件", value: "/Users/example/notes.md")
        ])
        XCTAssertEqual(
            content.actions.map(\.id),
            [.copyPath, .revealInFinder, .openClaudeCode, .openClaudeCodeSkipConfirmation]
        )
    }

    func testFilePanelAppendsConfiguredWindowLayoutButtons() {
        let content = SuperPanelContent.fileSystem(
            item: .testItem(
                kind: .folder,
                displayTitle: "Project",
                originalPath: "/Users/example/Project",
                sourceApp: "访达"
            ),
            windowLayoutButtons: [
                WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf]),
                WindowLayoutButton(id: "custom.focus", title: "专注布局", modes: [.centered, .maximize])
            ]
        )

        XCTAssertEqual(
            content.actions.suffix(2).map(\.id),
            [.windowLayoutButton("mode.leftHalf"), .windowLayoutButton("custom.focus")]
        )
        XCTAssertEqual(
            content.actions.suffix(2).map(\.title),
            ["左半屏", "专注布局"]
        )
    }
}

private extension ClipboardItem {
    static func testItem(
        kind: ClipboardContentKind,
        displayTitle: String,
        originalPath: String?,
        sourceApp: String?
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: displayTitle,
            searchableText: [displayTitle, originalPath].compactMap { $0 }.joined(separator: " "),
            text: nil,
            originalPath: originalPath,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: sourceApp,
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }
}
