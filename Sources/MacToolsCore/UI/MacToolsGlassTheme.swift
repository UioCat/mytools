import SwiftUI

public enum MacToolsGlassTheme {
    public static let windowBackground = LinearGradient(
        colors: [
            Color.white.opacity(0.24),
            Color(red: 0.880, green: 0.940, blue: 1.000).opacity(0.18),
            Color.white.opacity(0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let panelTint = Color(red: 0.940, green: 0.970, blue: 1.000)
    public static let moduleTint = Color(red: 0.900, green: 0.955, blue: 1.000)
    public static let activeBlue = Color(red: 0.030, green: 0.430, blue: 1.000)
    public static let activeBlueSoft = Color(red: 0.065, green: 0.315, blue: 0.720)
    public static let success = Color(red: 0.250, green: 0.900, blue: 0.520)
    public static let warning = Color(red: 1.000, green: 0.780, blue: 0.220)
    public static let destructive = Color(red: 1.000, green: 0.270, blue: 0.250)

    public static let textPrimary = Color(red: 0.055, green: 0.075, blue: 0.105).opacity(0.96)
    public static let textSecondary = Color(red: 0.115, green: 0.145, blue: 0.190).opacity(0.76)
    public static let textTertiary = Color(red: 0.180, green: 0.220, blue: 0.285).opacity(0.58)
    public static let textDisabled = Color(red: 0.220, green: 0.260, blue: 0.320).opacity(0.34)
    public static let divider = Color(red: 0.080, green: 0.115, blue: 0.165).opacity(0.12)
    public static let border = Color(red: 0.080, green: 0.125, blue: 0.190).opacity(0.18)
    public static let strongBorder = Color(red: 0.070, green: 0.115, blue: 0.185).opacity(0.30)
    public static let rowHover = Color(red: 0.060, green: 0.160, blue: 0.300).opacity(0.075)
    public static let fieldFill = Color.white.opacity(0.36)

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
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.13))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.30), lineWidth: 1)
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
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.18 : 0.30))
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(configuration.isPressed ? 0.10 : 0.22),
                                Color.clear,
                                color.opacity(configuration.isPressed ? 0.12 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .liquidGlassInteractiveModule(cornerRadius: cornerRadius, isSelected: true)
            .shadow(color: color.opacity(configuration.isPressed ? 0.12 : 0.26), radius: 14, x: 0, y: 7)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(color.opacity(0.08))
            )
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.20),
                                Color.clear,
                                color.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .liquidGlassChip(cornerRadius: size * 0.28)
    }
}
