import AppKit
import Foundation

public enum SuperPanelLayout {
    public static let scale: CGFloat = 0.5
    public static let translationScale: CGFloat = scale * 4 / 3

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

    public static let standardPrimaryActionRowHeight: CGFloat = 58
    public static let translationActionRowHeight: CGFloat = 44
    public static let translationActionIconSize: CGFloat = 28
    public static let translationActionIconFontSize: CGFloat = 14
    public static let translationActionTitleFontSize: CGFloat = 15
    public static let translationActionSpacing: CGFloat = 10
    public static let translationActionHorizontalPadding: CGFloat = 16
    public static let translationActionVerticalPadding: CGFloat = 8

    public static func panelSize(for content: SuperPanelContent) -> CGSize {
        let isExpandedPanel = content.kind == .fileSystem || content.kind == .windowLayout
        let previewRowsHeight = estimatedPreviewRowsHeight(
            for: content,
            isExpandedPanel: isExpandedPanel
        )
        let primaryActionCount = content.actions.filter { !$0.id.isWindowLayoutButton }.count
        let windowLayoutActionCount = content.actions.count - primaryActionCount
        let windowLayoutRows = CGFloat((windowLayoutActionCount + 1) / 2)
        let primaryActionRowHeight = content.kind == .text
            ? translationActionRowHeight
            : standardPrimaryActionRowHeight
        let actionsHeight = CGFloat(primaryActionCount) * primaryActionRowHeight
            + (windowLayoutActionCount > 0 ? 42 + windowLayoutRows * 44 : 0)
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
                ), 130), 620)
            )
        }

        let contentScale = content.kind == .text ? translationScale : scale
        return CGSize(
            width: 500 * contentScale,
            height: min(max(legacyHeight, 260), 620) * contentScale
        )
    }

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

    private static func previewLineCount(for value: String) -> Int {
        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let valueWidth: CGFloat = 320 - 44 - 48 - 12
        let bounds = (value as NSString).boundingRect(
            with: CGSize(width: valueWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        return max(1, Int(ceil(bounds.height / lineHeight)))
    }

    private static func expandedPanelHeight(
        previewRowsHeight: CGFloat,
        primaryActionCount: Int,
        windowLayoutActionCount: Int,
        windowLayoutRows: CGFloat
    ) -> CGFloat {
        let headerHeight = max(
            headerIconSize,
            headerTitleFontSize + headerTextSpacing + headerSubtitleFontSize
        ) + headerTopPadding + headerBottomPadding
        let dividerHeight: CGFloat = 1
        let actionSectionVerticalPadding: CGFloat = 16
        let primaryActionsHeight = CGFloat(primaryActionCount) * standardPrimaryActionRowHeight
        let previewHeight = previewRowsHeight > 0 ? previewRowsHeight + dividerHeight : 0
        let groupDividerHeight = primaryActionCount > 0 && windowLayoutActionCount > 0
            ? dividerHeight
            : 0
        let windowLayoutHeight = windowLayoutActionCount > 0
            ? 42 + windowLayoutRows * 44
            : 0

        return headerHeight
            + dividerHeight
            + previewHeight
            + actionSectionVerticalPadding
            + primaryActionsHeight
            + groupDividerHeight
            + windowLayoutHeight
    }

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
