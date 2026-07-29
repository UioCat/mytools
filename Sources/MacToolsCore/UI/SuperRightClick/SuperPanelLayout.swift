// 超级右键面板的尺寸与动作区布局策略。
// 根据内容和按钮数量计算稳定高度，不读取当前屏幕或窗口状态。

import AppKit
import Foundation

/// 描述 `SuperPanelLayout` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum SuperPanelLayout {
    public static let scale: CGFloat = 0.5

    public static let headerIconSize: CGFloat = 36
    public static let headerIconFontSize: CGFloat = 16
    public static let headerTitleFontSize: CGFloat = 16
    public static let headerSubtitleFontSize: CGFloat = 11
    public static let headerTrailingIconFontSize: CGFloat = 18
    public static let headerAccessorySize: CGFloat = 20
    public static let headerSpacing: CGFloat = 10
    public static let headerTextSpacing: CGFloat = 2
    public static let headerHorizontalPadding: CGFloat = 14
    public static let headerTopPadding: CGFloat = 12
    public static let headerBottomPadding: CGFloat = 10

    public static let standardPrimaryActionRowHeight = MacToolsControlMetrics.superPanelActionRowHeight
    public static let translationPanelWidth: CGFloat = 420
    public static let textTransitPanelWidth: CGFloat = 320
    public static let translationActionSectionHeight: CGFloat = 56
    public static let translationActionButtonHeight = MacToolsControlMetrics.textActionHeight
    public static let translationActionTitleFontSize = MacToolsControlMetrics.textActionFontSize
    public static let translationActionSpacing: CGFloat = 8
    public static let translationActionSectionHorizontalPadding: CGFloat = 12
    public static let translationActionButtonHorizontalPadding = MacToolsControlMetrics.textActionHorizontalPadding

    private static let previewLabelWidth: CGFloat = 48
    private static let previewSpacing: CGFloat = 12
    private static let previewHorizontalPadding: CGFloat = 22
    private static let previewRowVerticalPadding: CGFloat = 8
    private static let textPreviewSectionVerticalPadding: CGFloat = 8
    private static let textPreviewFontSize: CGFloat = 14
    private static let standardActionSectionVerticalPadding: CGFloat = 16
    private static let windowLayoutSectionVerticalPadding: CGFloat = 24
    private static let windowLayoutHeaderToGridSpacing: CGFloat = 10
    private static let windowLayoutGridSpacing: CGFloat = 8
    private static let windowLayoutHeaderFontSize: CGFloat = 12
    private static let maximumPanelHeight: CGFloat = 620

    /// 构建并返回 `panelSize` 对应的 SwiftUI 界面内容或展示状态。
    public static func panelSize(for content: SuperPanelContent) -> CGSize {
        if content.kind == .text {
            return translationPanelSize(for: content)
        }
        if content.kind == .textTransit {
            return textTransitPanelSize(for: content)
        }

        let isExpandedPanel = content.kind == .fileSystem || content.kind == .windowLayout
        let previewRowsHeight = estimatedPreviewRowsHeight(
            for: content,
            isExpandedPanel: isExpandedPanel
        )
        let primaryActionCount = content.actions.filter { !$0.id.isWindowLayoutButton }.count
        let windowLayoutActionCount = content.actions.count - primaryActionCount
        let windowLayoutRows = (windowLayoutActionCount + 1) / 2
        let actionsHeight = CGFloat(primaryActionCount) * standardPrimaryActionRowHeight
            + windowLayoutSectionHeight(rowCount: windowLayoutRows)
        let legacyHeight = 92
            + previewRowsHeight
            + estimatedExpandedTextHeight(for: content)
            + actionsHeight
            + 22
        if isExpandedPanel {
            return CGSize(
                width: 320,
                height: min(max(expandedPanelHeight(
                    previewRowsHeight: previewRowsHeight,
                    primaryActionCount: primaryActionCount,
                    windowLayoutActionCount: windowLayoutActionCount,
                    windowLayoutRows: windowLayoutRows
                ), 130), maximumPanelHeight)
            )
        }

        return CGSize(
            width: 500 * scale,
            height: min(max(legacyHeight, 260), maximumPanelHeight) * scale
        )
    }

    /// 构建并返回 `translationPanelSize` 对应的 SwiftUI 界面内容或展示状态。
    private static func translationPanelSize(for content: SuperPanelContent) -> CGSize {
        let headerHeight = panelHeaderHeight
        let dividerHeight: CGFloat = 1
        let previewHeight = textPreviewHeight(
            for: content,
            panelWidth: translationPanelWidth
        )
        let actionHeight = content.actions.isEmpty ? 0 : translationActionSectionHeight
        let contentHeight = headerHeight
            + dividerHeight
            + previewHeight
            + (content.previewRows.isEmpty ? 0 : dividerHeight)
            + actionHeight

        return CGSize(
            width: translationPanelWidth,
            height: min(contentHeight, maximumPanelHeight)
        )
    }

    /// 构建并返回 `textTransitPanelSize` 对应的 SwiftUI 界面内容或展示状态。
    private static func textTransitPanelSize(for content: SuperPanelContent) -> CGSize {
        let dividerHeight: CGFloat = 1
        let previewHeight = textPreviewHeight(
            for: content,
            panelWidth: textTransitPanelWidth
        )
        let primaryActionCount = content.actions.filter { !$0.id.isWindowLayoutButton }.count
        let internalActionDividers = CGFloat(max(primaryActionCount - 1, 0))
        let actionHeight = primaryActionCount == 0
            ? 0
            : standardActionSectionVerticalPadding
                + CGFloat(primaryActionCount) * standardPrimaryActionRowHeight
                + internalActionDividers
        let contentHeight = panelHeaderHeight
            + dividerHeight
            + previewHeight
            + (content.previewRows.isEmpty ? 0 : dividerHeight)
            + actionHeight

        return CGSize(
            width: textTransitPanelWidth,
            height: min(contentHeight, maximumPanelHeight)
        )
    }

    /// 构建并返回 `textPreviewHeight` 对应的 SwiftUI 界面内容或展示状态。
    private static func textPreviewHeight(
        for content: SuperPanelContent,
        panelWidth: CGFloat
    ) -> CGFloat {
        guard !content.previewRows.isEmpty else {
            return 0
        }

        let internalDividersHeight = CGFloat(max(content.previewRows.count - 1, 0))
        let rowsHeight = content.previewRows.reduce(0) { height, row in
            height + textPreviewRowHeight(
                for: row,
                contentKind: content.kind,
                panelWidth: panelWidth
            )
        }
        return rowsHeight
            + internalDividersHeight
            + textPreviewSectionVerticalPadding * 2
    }

    /// 构建并返回 `textPreviewRowHeight` 对应的 SwiftUI 界面内容或展示状态。
    private static func textPreviewRowHeight(
        for row: SuperPanelPreviewRow,
        contentKind: SuperPanelKind,
        panelWidth: CGFloat
    ) -> CGFloat {
        let speechControlWidth = row.speechRequest == nil
            ? 0
            : previewSpacing + MacToolsControlMetrics.inlineIconSize.width
        let valueWidth = panelWidth
            - previewHorizontalPadding * 2
            - previewLabelWidth
            - previewSpacing
            - speechControlWidth
        let font = NSFont.systemFont(ofSize: textPreviewFontSize, weight: .medium)
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        let bounds = (row.value as NSString).boundingRect(
            with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let maximumTextHeight = SuperPanelPreviewLineLimitPolicy
            .lineLimit(for: contentKind, row: row)
            .map { CGFloat($0) * lineHeight }
            ?? .greatestFiniteMagnitude
        let textHeight = max(lineHeight, min(ceil(bounds.height), maximumTextHeight))
        let contentHeight = max(
            textHeight,
            row.speechRequest == nil ? 0 : MacToolsControlMetrics.inlineIconSize.height
        )
        return contentHeight + previewRowVerticalPadding * 2
    }

    /// 按预览行的实际换行数估算展开面板高度，紧凑面板固定按单行计算。
    private static func estimatedPreviewRowsHeight(
        for content: SuperPanelContent,
        isExpandedPanel: Bool
    ) -> CGFloat {
        let singleLineRowHeight: CGFloat = 46
        guard isExpandedPanel else {
            return CGFloat(content.previewRows.count) * singleLineRowHeight
        }

        let additionalLineHeight: CGFloat = 17
        return content.previewRows.reduce(0) { height, row in
            let measuredLineCount = max(
                1,
                min(
                    SuperPanelPreviewLineLimitPolicy.lineLimit(for: content.kind, row: row) ?? 1,
                    previewLineCount(for: row.value)
                )
            )
            return height
                + singleLineRowHeight
                + CGFloat(measuredLineCount - 1) * additionalLineHeight
        }
    }

    /// 使用与预览文本一致的字体和可用宽度估算文本行数。
    private static func previewLineCount(for value: String) -> Int {
        let font = NSFont.systemFont(ofSize: textPreviewFontSize, weight: .medium)
        let valueWidth: CGFloat = 320
            - previewHorizontalPadding * 2
            - previewLabelWidth
            - previewSpacing
        let bounds = (value as NSString).boundingRect(
            with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        return max(1, Int(ceil(bounds.height / lineHeight)))
    }

    /// 构建并返回 `expandedPanelHeight` 对应的 SwiftUI 界面内容或展示状态。
    private static func expandedPanelHeight(
        previewRowsHeight: CGFloat,
        primaryActionCount: Int,
        windowLayoutActionCount: Int,
        windowLayoutRows: Int
    ) -> CGFloat {
        let dividerHeight: CGFloat = 1
        let primaryActionsHeight = CGFloat(primaryActionCount) * standardPrimaryActionRowHeight
        let primaryActionDividersHeight = CGFloat(max(primaryActionCount - 1, 0))
        let previewHeight = previewRowsHeight > 0 ? previewRowsHeight + dividerHeight : 0
        let groupDividerHeight = primaryActionCount > 0 && windowLayoutActionCount > 0
            ? dividerHeight
            : 0
        let windowLayoutHeight = windowLayoutSectionHeight(rowCount: windowLayoutRows)

        return panelHeaderHeight
            + dividerHeight
            + previewHeight
            + standardActionSectionVerticalPadding
            + primaryActionsHeight
            + primaryActionDividersHeight
            + groupDividerHeight
            + windowLayoutHeight
    }

    private static var panelHeaderHeight: CGFloat {
        max(
            headerIconSize,
            headerTitleFontSize + headerTextSpacing + headerSubtitleFontSize
        ) + headerTopPadding + headerBottomPadding
    }

    /// 构建并返回 `windowLayoutSectionHeight` 对应的 SwiftUI 界面内容或展示状态。
    private static func windowLayoutSectionHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else {
            return 0
        }

        let headerFont = NSFont.systemFont(ofSize: windowLayoutHeaderFontSize, weight: .semibold)
        let headerHeight = ceil(NSLayoutManager().defaultLineHeight(for: headerFont))
        let gridHeight = CGFloat(rowCount) * MacToolsControlMetrics.windowLayoutButtonHeight
            + CGFloat(max(rowCount - 1, 0)) * windowLayoutGridSpacing
        return windowLayoutSectionVerticalPadding
            + headerHeight
            + windowLayoutHeaderToGridSpacing
            + gridHeight
    }

    /// 构建并返回 `estimatedExpandedTextHeight` 对应的 SwiftUI 界面内容或展示状态。
    private static func estimatedExpandedTextHeight(for content: SuperPanelContent) -> CGFloat {
        guard content.kind == .text || content.kind == .textTransit else {
            return 0
        }

        let characterCount = content.previewRows.reduce(0) { total, row in
            total + row.value.count
        }
        guard characterCount > 120 else {
            return 0
        }

        return min(CGFloat(characterCount / 48) * 18, 280)
    }
}
