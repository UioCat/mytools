import AppKit
import SwiftUI

struct LiquidGlassSurfaceStyle {
    let cornerRadius: CGFloat
    let isNativeGlassInteractive: Bool
    let nativeTintOpacity: Double
    let legacyOverlayOpacity: Double
    let borderOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    static func panel(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: true,
            nativeTintOpacity: 0.06,
            legacyOverlayOpacity: 0.18,
            borderOpacity: 0.34,
            shadowOpacity: 0.30,
            shadowRadius: 34,
            shadowY: 22
        )
    }

    static func module(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: true,
            nativeTintOpacity: isSelected ? 0.14 : 0.08,
            legacyOverlayOpacity: isSelected ? 0.20 : 0.12,
            borderOpacity: isSelected ? 0.58 : 0.28,
            shadowOpacity: isSelected ? 0.26 : 0.18,
            shadowRadius: isSelected ? 18 : 12,
            shadowY: isSelected ? 9 : 6
        )
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    private var style: LiquidGlassSurfaceStyle {
        .panel(cornerRadius: cornerRadius)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.nativeLiquidGlassSurface(style: style)
        } else {
            content.legacyLiquidGlassSurface(style: style, material: .hudWindow)
        }
    }
}

struct LiquidGlassModuleModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool

    private var style: LiquidGlassSurfaceStyle {
        .module(cornerRadius: cornerRadius, isSelected: isSelected)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.nativeLiquidGlassSurface(style: style)
        } else {
            content.legacyLiquidGlassSurface(style: style, material: .popover)
        }
    }
}

private extension View {
    @available(macOS 26.0, *)
    func nativeLiquidGlassSurface(style: LiquidGlassSurfaceStyle) -> some View {
        self
            .background(nativeGlassBackground(style: style))
            .overlay(surfaceBorder(style: style))
            .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
    }

    func legacyLiquidGlassSurface(style: LiquidGlassSurfaceStyle, material: NSVisualEffectView.Material) -> some View {
        self
            .background(
                ZStack {
                    VisualEffectBackground(material: material)
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(style.legacyOverlayOpacity))
                    surfaceHighlight(style: style)
                }
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            )
            .overlay(surfaceBorder(style: style))
            .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
    }

    @available(macOS 26.0, *)
    func nativeGlassBackground(style: LiquidGlassSurfaceStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        return ZStack {
            shape
                .fill(Color.white.opacity(0.05))
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(style.nativeTintOpacity))
                        .interactive(style.isNativeGlassInteractive),
                    in: shape
                )
            surfaceHighlight(style: style)
        }
        .clipShape(shape)
    }

    func surfaceHighlight(style: LiquidGlassSurfaceStyle) -> some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.02),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
    }

    func surfaceBorder(style: LiquidGlassSurfaceStyle) -> some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(style.borderOpacity),
                        Color.white.opacity(style.borderOpacity * 0.42),
                        Color.white.opacity(style.borderOpacity * 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: style.borderOpacity > 0.5 ? 1.4 : 1
            )
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = .active
    }
}

public extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 28) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassModule(cornerRadius: CGFloat = 22, isSelected: Bool = false) -> some View {
        modifier(LiquidGlassModuleModifier(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}
