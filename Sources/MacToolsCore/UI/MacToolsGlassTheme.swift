// `MacToolsGlassTheme` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import SwiftUI

/// 描述 `MacToolsGlassTheme` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum MacToolsGlassTheme {
    public static let activeBlue = Color.accentColor
    public static let activeBlueSoft = Color.accentColor.opacity(0.72)
    public static let selectionBlue = Color(nsColor: .systemBlue)
    public static let success = Color.green
    public static let warning = Color.orange
    public static let destructive = Color.red

    public static let textPrimary = Color.primary.opacity(0.96)
    public static let textSecondary = Color.secondary.opacity(0.82)
    public static let textTertiary = Color.secondary.opacity(0.62)
    public static let textDisabled = Color.secondary.opacity(0.34)
    public static let divider = Color.primary.opacity(0.10)
    public static let border = Color.primary.opacity(0.14)
    public static let strongBorder = Color.primary.opacity(0.24)
    public static let rowHover = Color.accentColor.opacity(0.075)
    public static let fieldFill = Color.primary.opacity(0.055)

    /// 构建并返回 `statusColor` 对应的 SwiftUI 界面内容或展示状态。
    public static func statusColor(isEnabled: Bool) -> Color {
        isEnabled ? success : warning
    }
}

/// 描述 `MacToolsControlMetrics` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum MacToolsControlMetrics {
    public static let textActionHeight: CGFloat = 40
    public static let textActionFontSize: CGFloat = 14
    public static let textActionHorizontalPadding: CGFloat = 16

    public static let inlineIconSize = CGSize(width: 32, height: 32)
    public static let toolbarIconSize = CGSize(width: 40, height: 40)

    public static let sidebarNavigationHeight: CGFloat = 44
    public static let clipboardCategoryHeight: CGFloat = 36
    public static let clipboardCategoryMinimumWidth: CGFloat = 96
    public static let superPanelActionRowHeight: CGFloat = 56
    public static let windowLayoutButtonHeight: CGFloat = 40
    public static let settingsRowButtonMinimumHeight: CGFloat = 44
}

/// 封装 `GlassStatusPill` 在 SwiftUI 展示层中的值语义和相关操作。
struct GlassStatusPill: View {
    let title: String
    let systemImage: String?
    let color: Color

    /// 创建 `GlassStatusPill`，保存传入依赖并建立初始状态。
    init(_ title: String, systemImage: String? = nil, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(
            .regular.tint(color.opacity(0.18)),
            in: .capsule
        )
    }
}

/// 封装 `GlassPrimaryButtonStyle` 在 SwiftUI 展示层中的值语义和相关操作。
public struct GlassPrimaryButtonStyle: ButtonStyle {
    var color: Color = MacToolsGlassTheme.activeBlue
    var cornerRadius: CGFloat = 14

    /// 创建 `GlassPrimaryButtonStyle`，保存传入依赖并建立初始状态。
    public init(color: Color = MacToolsGlassTheme.activeBlue, cornerRadius: CGFloat = 14) {
        self.color = color
        self.cornerRadius = cornerRadius
    }

    /// 构造并返回 `makeBody` 所描述的 SwiftUI 展示层对象。
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.horizontal, MacToolsControlMetrics.textActionHorizontalPadding)
            .frame(minHeight: MacToolsControlMetrics.textActionHeight)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(
                .regular
                    .tint(color)
                    .interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

/// 封装 `GlassIconBadge` 在 SwiftUI 展示层中的值语义和相关操作。
struct GlassIconBadge: View {
    let systemName: String
    var color: Color = MacToolsGlassTheme.activeBlue
    var size: CGFloat = 48
    var iconSize: CGFloat = 20

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .glassEffect(
                .regular.tint(color.opacity(0.16)),
                in: .rect(cornerRadius: size * 0.28)
            )
    }
}
