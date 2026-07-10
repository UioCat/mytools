import SwiftUI

public enum MacToolsGlassTheme {
    public static let activeBlue = Color.accentColor
    public static let activeBlueSoft = Color.accentColor.opacity(0.72)
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

    public static func statusColor(isEnabled: Bool) -> Color {
        isEnabled ? success : warning
    }
}

struct GlassStatusPill: View {
    let title: String
    let systemImage: String?
    let color: Color

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

public struct GlassPrimaryButtonStyle: ButtonStyle {
    var color: Color = MacToolsGlassTheme.activeBlue
    var cornerRadius: CGFloat = 14

    public init(color: Color = MacToolsGlassTheme.activeBlue, cornerRadius: CGFloat = 14) {
        self.color = color
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .glassEffect(
                .regular
                    .tint(color)
                    .interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

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
