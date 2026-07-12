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
            [.textTransit]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["文本悬浮中转"]
        )
        XCTAssertFalse(content.actions.contains { $0.id.isWindowLayoutButton })
    }

    func testTextPanelShowsLoadingStateBeforeTranslationCompletes() {
        let content = SuperPanelContent.text(
            originalText: "hello",
            translation: nil,
            isTranslationLoading: true
        )

        XCTAssertEqual(content.headerTitle, "选中的文本 5 个")
        XCTAssertEqual(content.headerSubtitle, "翻译中...")
        XCTAssertTrue(content.showsLoadingIndicator)
        XCTAssertEqual(content.previewRows, [
            .init(label: "原文", value: "hello"),
            .init(label: "译文", value: "翻译中...")
        ])
        XCTAssertEqual(content.actions.map(\.id), [.textTransit])
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

    func testTextTransitPanelIgnoresConfiguredWindowLayoutButtons() {
        let content = SuperPanelContent.textTransit(
            text: "hello",
            windowLayoutButtons: [
                WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf])
            ]
        )

        XCTAssertEqual(content.actions.map(\.id), [.copyTransitText])
        XCTAssertFalse(content.actions.contains { $0.id.isWindowLayoutButton })
    }

    func testFolderPanelUsesDirectoryActions() {
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
            [.createNewFile, .copyPath, .openTerminal]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["新建文件", "复制当前路径", "在终端打开"]
        )
    }

    func testFilePanelKeepsOnlyCopyPathAction() {
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
            [.copyPath]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["复制文件路径"]
        )
    }

    func testImageFilePanelUsesTheSelectedFileActionSet() {
        let content = SuperPanelContent.fileSystem(
            item: .testItem(
                kind: .imageFile,
                displayTitle: "screenshot.png",
                originalPath: "/Users/example/screenshot.png",
                sourceApp: "访达"
            ),
            windowLayoutButtons: [
                WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf])
            ]
        )

        XCTAssertEqual(
            content.actions.map(\.id),
            [.copyPath, .windowLayoutButton("mode.leftHalf")]
        )
        XCTAssertEqual(
            content.actions.map(\.title),
            ["复制文件路径", "左半屏"]
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

    func testWindowLayoutOnlyPanelContainsNoSelectedContentActions() {
        let content = SuperPanelContent.windowLayoutOnly(
            windowLayoutButtons: [
                WindowLayoutButton(id: "mode.leftHalf", title: "左半屏", modes: [.leftHalf]),
                WindowLayoutButton(id: "mode.centered", title: "居中", modes: [.centered])
            ]
        )

        XCTAssertEqual(content.kind, .windowLayout)
        XCTAssertEqual(content.headerTitle, "窗口布局")
        XCTAssertEqual(content.headerSubtitle, "选择布局动作")
        XCTAssertEqual(content.headerSystemImage, "rectangle.3.group")
        XCTAssertEqual(content.previewRows, [])
        XCTAssertEqual(
            content.actions.map(\.id),
            [.windowLayoutButton("mode.leftHalf"), .windowLayoutButton("mode.centered")]
        )
        XCTAssertTrue(content.actions.allSatisfy(\.id.isWindowLayoutButton))
        XCTAssertFalse(content.showsLoadingIndicator)
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
