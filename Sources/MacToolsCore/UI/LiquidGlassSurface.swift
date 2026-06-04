import SwiftUI

struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(panelBackground)
            .overlay(panelBorder)
            .shadow(color: Color.black.opacity(0.36), radius: 34, x: 0, y: 22)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.clear,
                                Color.cyan.opacity(0.10),
                                Color.indigo.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.56),
                        Color.white.opacity(0.18),
                        Color.cyan.opacity(0.28),
                        Color.indigo.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
    }
}

struct LiquidGlassModuleModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(moduleBackground)
            .overlay(moduleBorder)
            .shadow(
                color: Color.black.opacity(isSelected ? 0.36 : 0.24),
                radius: isSelected ? 18 : 12,
                x: 0,
                y: isSelected ? 9 : 6
            )
    }

    private var moduleBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(isSelected ? 0.50 : 0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isSelected ? 0.22 : 0.14),
                                Color.white.opacity(0.02),
                                Color.cyan.opacity(isSelected ? 0.16 : 0.08),
                                Color.indigo.opacity(isSelected ? 0.16 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
    }

    private var moduleBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.70 : 0.40),
                        Color.white.opacity(isSelected ? 0.20 : 0.10),
                        Color.cyan.opacity(isSelected ? 0.58 : 0.20),
                        Color.indigo.opacity(isSelected ? 0.48 : 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected ? 1.8 : 1
            )
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 28) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassModule(cornerRadius: CGFloat = 22, isSelected: Bool = false) -> some View {
        modifier(LiquidGlassModuleModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}
