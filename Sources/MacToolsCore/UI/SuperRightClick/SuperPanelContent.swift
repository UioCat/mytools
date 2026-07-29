// 超级右键面板的不可变展示模型和动作描述。
// 负责将内容类型映射为预览与操作集合，不管理面板生命周期。

import Foundation

/// 描述 `SuperPanelKind` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum SuperPanelKind: Equatable {
    case text
    case textTransit
    case fileSystem
    case windowLayout
}

/// 描述 `SuperPanelFileSystemPresentation` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum SuperPanelFileSystemPresentation: Equatable {
    case selectedItem
    case finderCurrentDirectory
}

/// 描述 `SuperPanelActionID` 在 SwiftUI 展示层中可取的状态、选项或错误。
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

/// 封装 `SuperPanelPreviewRow` 在 SwiftUI 展示层中的值语义和相关操作。
public struct SuperPanelPreviewRow: Equatable {
    public var label: String
    public var value: String
    public var speechRequest: TranslationSpeechRequest?

    /// 创建 `SuperPanelPreviewRow`，保存传入依赖并建立初始状态。
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

/// 封装 `SuperPanelActionDescriptor` 在 SwiftUI 展示层中的值语义和相关操作。
public struct SuperPanelActionDescriptor: Equatable, Identifiable {
    public var id: SuperPanelActionID
    public var title: String
    public var systemImage: String

    /// 创建 `SuperPanelActionDescriptor`，保存传入依赖并建立初始状态。
    public init(id: SuperPanelActionID, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// 封装 `SuperPanelContent` 在 SwiftUI 展示层中的值语义和相关操作。
public struct SuperPanelContent: Equatable {
    public var kind: SuperPanelKind
    public var headerTitle: String
    public var headerSubtitle: String
    public var headerSystemImage: String
    public var previewRows: [SuperPanelPreviewRow]
    public var actions: [SuperPanelActionDescriptor]
    public var showsLoadingIndicator: Bool

    /// 创建 `SuperPanelContent`，保存传入依赖并建立初始状态。
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

    /// 构建并返回 `text` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `textTransit` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `fileSystem` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `windowLayoutOnly` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `windowLayoutActionDescriptors` 对应的 SwiftUI 界面内容或展示状态。
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
