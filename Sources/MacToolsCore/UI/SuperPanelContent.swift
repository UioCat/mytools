import Foundation

public enum SuperPanelKind: Equatable {
    case text
    case textTransit
    case fileSystem
    case windowLayout
}

public enum SuperPanelFileSystemPresentation: Equatable {
    case selectedItem
    case finderCurrentDirectory
}

public enum SuperPanelActionID: Equatable, Hashable {
    case copyTranslatedText
    case textTransit
    case copyTransitText
    case copyPath
    case createNewFile
    case openTerminal
    case revealInFinder
    case openClaudeCode
    case openClaudeCodeSkipConfirmation
    case windowLayoutButton(String)

    public var rawValue: String {
        switch self {
        case .copyTranslatedText:
            return "copyTranslatedText"
        case .textTransit:
            return "textTransit"
        case .copyTransitText:
            return "copyTransitText"
        case .copyPath:
            return "copyPath"
        case .createNewFile:
            return "createNewFile"
        case .openTerminal:
            return "openTerminal"
        case .revealInFinder:
            return "revealInFinder"
        case .openClaudeCode:
            return "openClaudeCode"
        case .openClaudeCodeSkipConfirmation:
            return "openClaudeCodeSkipConfirmation"
        case .windowLayoutButton(let id):
            return "windowLayoutButton.\(id)"
        }
    }

    public var isWindowLayoutButton: Bool {
        if case .windowLayoutButton = self {
            return true
        }
        return false
    }
}

public struct SuperPanelPreviewRow: Equatable {
    public var label: String
    public var value: String
    public var speechRequest: TranslationSpeechRequest?

    public init(
        label: String,
        value: String,
        speechRequest: TranslationSpeechRequest? = nil
    ) {
        self.label = label
        self.value = value
        self.speechRequest = speechRequest
    }
}

public struct SuperPanelActionDescriptor: Equatable, Identifiable {
    public var id: SuperPanelActionID
    public var title: String
    public var systemImage: String

    public init(id: SuperPanelActionID, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

public struct SuperPanelContent: Equatable {
    public var kind: SuperPanelKind
    public var headerTitle: String
    public var headerSubtitle: String
    public var headerSystemImage: String
    public var previewRows: [SuperPanelPreviewRow]
    public var actions: [SuperPanelActionDescriptor]
    public var showsLoadingIndicator: Bool

    public init(
        kind: SuperPanelKind,
        headerTitle: String,
        headerSubtitle: String,
        headerSystemImage: String,
        previewRows: [SuperPanelPreviewRow],
        actions: [SuperPanelActionDescriptor],
        showsLoadingIndicator: Bool = false
    ) {
        self.kind = kind
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.headerSystemImage = headerSystemImage
        self.previewRows = previewRows
        self.actions = actions
        self.showsLoadingIndicator = showsLoadingIndicator
    }

    public static func text(
        originalText: String,
        translation: Result<TranslationResponse, TranslationError>?,
        isTranslationLoading: Bool = false,
        windowLayoutButtons _: [WindowLayoutButton] = []
    ) -> SuperPanelContent {
        let normalizedText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = normalizedText.isEmpty ? originalText : normalizedText
        let originalSpeechRequest = normalizedText.isEmpty
            ? nil
            : TranslationSpeechRequest(
                text: displayText,
                languageCode: TranslationSpeechLanguagePolicy.originalLanguageCode(for: displayText),
                source: .superRightClick
            )
        var previewRows = [
            SuperPanelPreviewRow(
                label: "原文",
                value: displayText,
                speechRequest: originalSpeechRequest
            )
        ]
        var actions: [SuperPanelActionDescriptor] = []
        let subtitle: String

        switch (isTranslationLoading, translation) {
        case (true, _):
            subtitle = "翻译中..."
            previewRows.append(.init(label: "译文", value: "翻译中..."))
        case (_, .success(let response)):
            let translatedText = response.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            subtitle = translatedText.isEmpty ? "翻译结果为空" : translatedText
            let speechRequest = translatedText.isEmpty
                ? nil
                : TranslationSpeechRequest(
                    text: translatedText,
                    languageCode: TranslationSpeechLanguagePolicy.translatedLanguageCode(forOriginalText: displayText),
                    source: .superRightClick
                )
            previewRows.append(
                .init(
                    label: "译文",
                    value: subtitle,
                    speechRequest: speechRequest
                )
            )
            actions.append(
                .init(id: .copyTranslatedText, title: "复制译文", systemImage: "doc.on.doc")
            )
        case (_, .failure(.providerNotConfigured)):
            subtitle = "翻译未配置"
            previewRows.append(
                .init(label: "提示", value: "在设置里填写 DASHSCOPE_API_KEY 后可显示翻译结果")
            )
        case (_, .failure(.networkUnavailable)):
            subtitle = "翻译失败"
            previewRows.append(.init(label: "提示", value: "无法连接到百炼服务，请检查网络后重试"))
        case (_, .failure(.providerFailure(let message))):
            subtitle = "翻译失败"
            previewRows.append(.init(label: "提示", value: message))
        case (_, nil):
            subtitle = displayText
        }

        actions.append(contentsOf: [
            .init(id: .textTransit, title: "文本悬浮中转", systemImage: "pin.fill")
        ])

        return SuperPanelContent(
            kind: .text,
            headerTitle: "选中的文本 \(displayText.count) 个",
            headerSubtitle: subtitle,
            headerSystemImage: "circle.grid.3x3.fill",
            previewRows: previewRows,
            actions: actions,
            showsLoadingIndicator: isTranslationLoading
        )
    }

    public static func textTransit(
        text: String,
        windowLayoutButtons _: [WindowLayoutButton] = []
    ) -> SuperPanelContent {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = normalizedText.isEmpty ? text : normalizedText

        return SuperPanelContent(
            kind: .textTransit,
            headerTitle: "文本悬浮中转",
            headerSubtitle: "\(displayText.count) 个字符",
            headerSystemImage: "pin.fill",
            previewRows: [.init(label: "文本", value: displayText)],
            actions: [
                .init(id: .copyTransitText, title: "复制文本", systemImage: "doc.on.doc")
            ]
        )
    }

    public static func fileSystem(
        item: ClipboardItem,
        windowLayoutButtons: [WindowLayoutButton] = [],
        presentation: SuperPanelFileSystemPresentation = .selectedItem
    ) -> SuperPanelContent {
        let itemType = item.kind == .folder ? "文件夹" : "文件"
        let path = item.originalPath ?? item.displayTitle
        var actions: [SuperPanelActionDescriptor]

        switch presentation {
        case .selectedItem:
            actions = [
                .init(id: .copyPath, title: "复制文件路径", systemImage: "doc.on.doc")
            ]
        case .finderCurrentDirectory:
            actions = [
                .init(id: .createNewFile, title: "新建文件", systemImage: "plus.square.fill"),
                .init(id: .copyPath, title: "复制当前路径", systemImage: "folder.fill"),
                .init(id: .openTerminal, title: "在终端打开", systemImage: "terminal.fill")
            ]
        }
        actions.append(contentsOf: windowLayoutActionDescriptors(from: windowLayoutButtons))

        return SuperPanelContent(
            kind: .fileSystem,
            headerTitle: item.sourceApp?.isEmpty == false ? item.sourceApp! : "访达",
            headerSubtitle: item.displayTitle,
            headerSystemImage: item.kind == .folder ? "folder.fill" : "doc.fill",
            previewRows: [.init(label: itemType, value: path)],
            actions: actions
        )
    }

    public static func windowLayoutOnly(
        windowLayoutButtons: [WindowLayoutButton]
    ) -> SuperPanelContent {
        SuperPanelContent(
            kind: .windowLayout,
            headerTitle: "窗口布局",
            headerSubtitle: "选择布局动作",
            headerSystemImage: "rectangle.3.group",
            previewRows: [],
            actions: windowLayoutActionDescriptors(from: windowLayoutButtons)
        )
    }

    private static func windowLayoutActionDescriptors(
        from buttons: [WindowLayoutButton]
    ) -> [SuperPanelActionDescriptor] {
        buttons.map { button in
            SuperPanelActionDescriptor(
                id: .windowLayoutButton(button.id),
                title: button.title,
                systemImage: button.systemImage
            )
        }
    }
}
