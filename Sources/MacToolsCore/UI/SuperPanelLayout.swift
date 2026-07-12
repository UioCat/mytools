import Foundation

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

    public static func panelSize(for content: SuperPanelContent) -> CGSize {
        let previewRowsHeight = CGFloat(content.previewRows.count) * 46
        let primaryActionCount = content.actions.filter { !$0.id.isWindowLayoutButton }.count
        let windowLayoutActionCount = content.actions.count - primaryActionCount
        let windowLayoutRows = CGFloat((windowLayoutActionCount + 1) / 2)
        let actionsHeight = CGFloat(primaryActionCount) * 58
            + (windowLayoutActionCount > 0 ? 42 + windowLayoutRows * 44 : 0)
        let legacyHeight = 92
            + previewRowsHeight
            + estimatedExpandedTextHeight(for: content)
            + actionsHeight
            + 22
        let cappedLegacyHeight = min(max(legacyHeight, 260), 620)
        let legacyWidth: CGFloat = content.kind == .fileSystem ? 520 : 500

        return CGSize(
            width: legacyWidth * scale,
            height: cappedLegacyHeight * scale
        )
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
