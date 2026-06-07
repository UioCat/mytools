import Foundation

public enum SuperPanelKind: Equatable {
    case text
    case textTransit
    case fileSystem
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

    public init(label: String, value: String) {
        self.label = label
        self.value = value
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

    public init(
        kind: SuperPanelKind,
        headerTitle: String,
        headerSubtitle: String,
        headerSystemImage: String,
        previewRows: [SuperPanelPreviewRow],
        actions: [SuperPanelActionDescriptor]
    ) {
        self.kind = kind
        self.headerTitle = headerTitle
        self.headerSubtitle = headerSubtitle
        self.headerSystemImage = headerSystemImage
        self.previewRows = previewRows
        self.actions = actions
    }

    public static func text(
        originalText: String,
        translation: Result<TranslationResponse, TranslationError>?,
        windowLayoutButtons: [WindowLayoutButton] = []
    ) -> SuperPanelContent {
        let normalizedText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = normalizedText.isEmpty ? originalText : normalizedText
        var previewRows = [SuperPanelPreviewRow(label: "原文", value: displayText)]
        var actions: [SuperPanelActionDescriptor] = []
        let subtitle: String

        switch translation {
        case .success(let response):
            let translatedText = response.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            subtitle = translatedText.isEmpty ? "翻译结果为空" : translatedText
            previewRows.append(.init(label: "译文", value: subtitle))
            actions.append(
                .init(id: .copyTranslatedText, title: "复制译文", systemImage: "doc.on.doc")
            )
        case .failure(.providerNotConfigured):
            subtitle = "翻译未配置"
            previewRows.append(
                .init(label: "提示", value: "在设置里填写 DASHSCOPE_API_KEY 后可显示翻译结果")
            )
        case .failure(.networkUnavailable):
            subtitle = "翻译失败"
            previewRows.append(.init(label: "提示", value: "无法连接到百炼服务，请检查网络后重试"))
        case .failure(.providerFailure(let message)):
            subtitle = "翻译失败"
            previewRows.append(.init(label: "提示", value: message))
        case nil:
            subtitle = displayText
        }

        actions.append(contentsOf: [
            .init(id: .textTransit, title: "文本悬浮中转", systemImage: "pin.fill")
        ])
        actions.append(contentsOf: windowLayoutActionDescriptors(from: windowLayoutButtons))

        return SuperPanelContent(
            kind: .text,
            headerTitle: "选中的文本 \(displayText.count) 个",
            headerSubtitle: subtitle,
            headerSystemImage: "circle.grid.3x3.fill",
            previewRows: previewRows,
            actions: actions
        )
    }

    public static func textTransit(
        text: String,
        windowLayoutButtons: [WindowLayoutButton] = []
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
            ] + windowLayoutActionDescriptors(from: windowLayoutButtons)
        )
    }

    public static func fileSystem(
        item: ClipboardItem,
        windowLayoutButtons: [WindowLayoutButton] = []
    ) -> SuperPanelContent {
        let itemType = item.kind == .folder ? "文件夹" : "文件"
        let path = item.originalPath ?? item.displayTitle
        var actions: [SuperPanelActionDescriptor]

        if item.kind == .folder {
            actions = [
                .init(id: .copyPath, title: "复制当前路径", systemImage: "folder.fill"),
                .init(id: .createNewFile, title: "新建文件", systemImage: "plus.square.fill"),
                .init(id: .openTerminal, title: "终端中打开", systemImage: "terminal.fill"),
                .init(id: .openClaudeCode, title: "Claude Code 打开", systemImage: "chevron.left.forwardslash.chevron.right"),
                .init(id: .openClaudeCodeSkipConfirmation, title: "Claude Code 打开（跳过确认）", systemImage: "chevron.left.forwardslash.chevron.right")
            ]
        } else {
            actions = [
                .init(id: .copyPath, title: "复制当前路径", systemImage: "folder.fill"),
                .init(id: .revealInFinder, title: "在访达中显示", systemImage: "folder"),
                .init(id: .openClaudeCode, title: "Claude Code 打开", systemImage: "chevron.left.forwardslash.chevron.right"),
                .init(id: .openClaudeCodeSkipConfirmation, title: "Claude Code 打开（跳过确认）", systemImage: "chevron.left.forwardslash.chevron.right")
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
