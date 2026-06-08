import AppKit
import SwiftUI

struct LiquidGlassSurfaceStyle {
    let cornerRadius: CGFloat
    let isNativeGlassInteractive: Bool
    let usesNativeGlassEffect: Bool
    let materialOpacity: Double
    let nativeBaseOpacity: Double
    let nativeTintOpacity: Double
    let legacyOverlayOpacity: Double
    let accentTintOpacity: Double
    let borderOpacity: Double
    let edgeDepthOpacity: Double
    let accentFocusOpacity: Double
    let highlightOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    static func panel(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: false,
            usesNativeGlassEffect: false,
            materialOpacity: 0.72,
            nativeBaseOpacity: 0.004,
            nativeTintOpacity: 0.005,
            legacyOverlayOpacity: 0.026,
            accentTintOpacity: 0,
            borderOpacity: 0.30,
            edgeDepthOpacity: 0.16,
            accentFocusOpacity: 0,
            highlightOpacity: 0.035,
            shadowOpacity: 0.13,
            shadowRadius: 24,
            shadowY: 12
        )
    }

    static func module(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: false,
            usesNativeGlassEffect: false,
            materialOpacity: isSelected ? 0.92 : 0.88,
            nativeBaseOpacity: isSelected ? 0.010 : 0.006,
            nativeTintOpacity: isSelected ? 0.038 : 0.016,
            legacyOverlayOpacity: isSelected ? 0.075 : 0.035,
            accentTintOpacity: isSelected ? 0.028 : 0,
            borderOpacity: isSelected ? 0.34 : 0.18,
            edgeDepthOpacity: isSelected ? 0.08 : 0.04,
            accentFocusOpacity: isSelected ? 0.16 : 0,
            highlightOpacity: isSelected ? 0.07 : 0.045,
            shadowOpacity: isSelected ? 0.09 : 0.05,
            shadowRadius: isSelected ? 8 : 4,
            shadowY: isSelected ? 3 : 2
        )
    }

    static func interactiveModule(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: true,
            usesNativeGlassEffect: false,
            materialOpacity: isSelected ? 0.92 : 0.88,
            nativeBaseOpacity: isSelected ? 0.010 : 0.006,
            nativeTintOpacity: isSelected ? 0.038 : 0.016,
            legacyOverlayOpacity: isSelected ? 0.075 : 0.035,
            accentTintOpacity: isSelected ? 0.028 : 0,
            borderOpacity: isSelected ? 0.34 : 0.18,
            edgeDepthOpacity: isSelected ? 0.08 : 0.04,
            accentFocusOpacity: isSelected ? 0.16 : 0,
            highlightOpacity: isSelected ? 0.07 : 0.045,
            shadowOpacity: isSelected ? 0.09 : 0.05,
            shadowRadius: isSelected ? 8 : 4,
            shadowY: isSelected ? 3 : 2
        )
    }

    static func chip(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: false,
            usesNativeGlassEffect: false,
            materialOpacity: 0.82,
            nativeBaseOpacity: 0.004,
            nativeTintOpacity: 0.012,
            legacyOverlayOpacity: 0.030,
            accentTintOpacity: 0,
            borderOpacity: 0.10,
            edgeDepthOpacity: 0.025,
            accentFocusOpacity: 0,
            highlightOpacity: 0.025,
            shadowOpacity: 0.02,
            shadowRadius: 2,
            shadowY: 1
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
            content.nativeLiquidGlassSurface(style: style, material: .underWindowBackground)
        } else {
            content.legacyLiquidGlassSurface(style: style, material: .underWindowBackground)
        }
    }
}

public enum LiquidGlassWindowPanelSurfacePlacement: Equatable {
    case afterSizing
}

public enum LiquidGlassWindowPanelAlignment: Equatable {
    case topLeading

    var swiftUIAlignment: Alignment {
        switch self {
        case .topLeading:
            return .topLeading
        }
    }
}

public struct LiquidGlassWindowPanelFrame: Equatable {
    public let minWidth: CGFloat
    public let idealWidth: CGFloat
    public let maxWidth: CGFloat
    public let minHeight: CGFloat
    public let idealHeight: CGFloat
    public let maxHeight: CGFloat
    public let alignment: LiquidGlassWindowPanelAlignment
    public var surfacePlacement: LiquidGlassWindowPanelSurfacePlacement { .afterSizing }

    public init(
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat,
        minHeight: CGFloat,
        idealHeight: CGFloat,
        maxHeight: CGFloat,
        alignment: LiquidGlassWindowPanelAlignment = .topLeading
    ) {
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }

    public static let mainWorkspace = LiquidGlassWindowPanelFrame(
        minWidth: 900,
        idealWidth: 1080,
        maxWidth: .infinity,
        minHeight: 620,
        idealHeight: 720,
        maxHeight: .infinity
    )

    public static let mainPanel = LiquidGlassWindowPanelFrame(
        minWidth: 720,
        idealWidth: 900,
        maxWidth: .infinity,
        minHeight: 480,
        idealHeight: 620,
        maxHeight: .infinity
    )

    public static let settings = LiquidGlassWindowPanelFrame(
        minWidth: 640,
        idealWidth: 820,
        maxWidth: 900,
        minHeight: 520,
        idealHeight: 680,
        maxHeight: 900
    )
}

private struct LiquidGlassWindowPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let clipCornerRadius: CGFloat
    let frame: LiquidGlassWindowPanelFrame

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: frame.minWidth,
                idealWidth: frame.idealWidth,
                maxWidth: frame.maxWidth,
                minHeight: frame.minHeight,
                idealHeight: frame.idealHeight,
                maxHeight: frame.maxHeight,
                alignment: frame.alignment.swiftUIAlignment
            )
            .liquidGlassPanel(cornerRadius: cornerRadius)
            .clipShape(RoundedRectangle(cornerRadius: clipCornerRadius, style: .continuous))
    }
}

struct LiquidGlassModuleModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    let isInteractive: Bool

    private var style: LiquidGlassSurfaceStyle {
        if isInteractive {
            return .interactiveModule(cornerRadius: cornerRadius, isSelected: isSelected)
        }

        return .module(cornerRadius: cornerRadius, isSelected: isSelected)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.nativeLiquidGlassSurface(style: style, material: .popover)
        } else {
            content.legacyLiquidGlassSurface(style: style, material: .popover)
        }
    }
}

struct LiquidGlassChipModifier: ViewModifier {
    let cornerRadius: CGFloat

    private var style: LiquidGlassSurfaceStyle {
        .chip(cornerRadius: cornerRadius)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.nativeLiquidGlassSurface(style: style, material: .popover)
        } else {
            content.legacyLiquidGlassSurface(style: style, material: .popover)
        }
    }
}

struct LiquidGlassGroupModifier: ViewModifier {
    let spacing: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    @available(macOS 26.0, *)
    func nativeLiquidGlassSurface(style: LiquidGlassSurfaceStyle, material: NSVisualEffectView.Material) -> some View {
        if style.usesNativeGlassEffect {
            self
                .background(nativeGlassBackground(style: style))
                .overlay(surfaceBorder(style: style))
                .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
                .shadow(
                    color: Color(nsColor: .controlAccentColor).opacity(style.accentFocusOpacity * 0.26),
                    radius: style.shadowRadius * 0.65,
                    x: 0,
                    y: style.shadowY * 0.45
                )
        } else {
            self.legacyLiquidGlassSurface(style: style, material: material)
        }
    }

    func legacyLiquidGlassSurface(style: LiquidGlassSurfaceStyle, material: NSVisualEffectView.Material) -> some View {
        self
            .background(
                ZStack {
                    VisualEffectBackground(material: material)
                        .opacity(style.materialOpacity)
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(style.legacyOverlayOpacity))
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlAccentColor).opacity(style.accentTintOpacity))
                    surfaceHighlight(style: style)
                }
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            )
            .overlay(surfaceBorder(style: style))
            .shadow(color: Color.black.opacity(style.shadowOpacity), radius: style.shadowRadius, x: 0, y: style.shadowY)
            .shadow(
                color: Color(nsColor: .controlAccentColor).opacity(style.accentFocusOpacity * 0.26),
                radius: style.shadowRadius * 0.65,
                x: 0,
                y: style.shadowY * 0.45
            )
    }

    @available(macOS 26.0, *)
    func nativeGlassBackground(style: LiquidGlassSurfaceStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        return ZStack {
            shape
                .fill(Color.white.opacity(style.nativeBaseOpacity))
                .glassEffect(
                    .regular
                        .tint(Color.white.opacity(style.nativeTintOpacity))
                        .interactive(style.isNativeGlassInteractive),
                    in: shape
                )
            shape
                .fill(Color(nsColor: .controlAccentColor).opacity(style.accentTintOpacity))
            surfaceHighlight(style: style)
        }
        .clipShape(shape)
    }

    func surfaceHighlight(style: LiquidGlassSurfaceStyle) -> some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(style.highlightOpacity),
                        Color.white.opacity(style.highlightOpacity * 0.42),
                        Color.white.opacity(style.highlightOpacity * 0.14),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.screen)
    }

    func surfaceBorder(style: LiquidGlassSurfaceStyle) -> some View {
        ZStack {
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

            if style.accentFocusOpacity > 0 {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .controlAccentColor).opacity(style.accentFocusOpacity),
                        lineWidth: 1.6
                    )
            }

            if style.edgeDepthOpacity > 0 {
                RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(style.edgeDepthOpacity * 0.38),
                                Color.black.opacity(style.edgeDepthOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: style.edgeDepthOpacity > 0.1 ? 1.2 : 0.8
                    )
                    .blendMode(.multiply)
            }
        }
    }
}

public struct LiquidGlassButtonStyle: ButtonStyle {
    private let cornerRadius: CGFloat
    private let isSelected: Bool
    private let minimumSize: CGSize?
    private let showsIdleSurface: Bool

    public init(
        cornerRadius: CGFloat = 22,
        isSelected: Bool = false,
        minimumSize: CGSize? = nil,
        showsIdleSurface: Bool = true
    ) {
        self.cornerRadius = cornerRadius
        self.isSelected = isSelected
        self.minimumSize = minimumSize
        self.showsIdleSurface = showsIdleSurface
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isActive = isSelected || configuration.isPressed

        configuration.label
            .frame(
                minWidth: minimumSize?.width,
                minHeight: minimumSize?.height
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .modifier(
                LiquidGlassButtonSurfaceModifier(
                    cornerRadius: cornerRadius,
                    isSelected: isActive,
                    showsSurface: showsIdleSurface || isActive
                )
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct LiquidGlassButtonSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    let showsSurface: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsSurface {
            content.liquidGlassInteractiveModule(cornerRadius: cornerRadius, isSelected: isSelected)
        } else {
            content
        }
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

    func liquidGlassWindowPanel(
        cornerRadius: CGFloat = 30,
        clipCornerRadius: CGFloat = 28,
        frame: LiquidGlassWindowPanelFrame
    ) -> some View {
        modifier(
            LiquidGlassWindowPanelModifier(
                cornerRadius: cornerRadius,
                clipCornerRadius: clipCornerRadius,
                frame: frame
            )
        )
    }

    func liquidGlassModule(cornerRadius: CGFloat = 22, isSelected: Bool = false) -> some View {
        modifier(
            LiquidGlassModuleModifier(
                cornerRadius: cornerRadius,
                isSelected: isSelected,
                isInteractive: false
            )
        )
    }

    func liquidGlassInteractiveModule(cornerRadius: CGFloat = 22, isSelected: Bool = false) -> some View {
        modifier(
            LiquidGlassModuleModifier(
                cornerRadius: cornerRadius,
                isSelected: isSelected,
                isInteractive: true
            )
        )
    }

    func liquidGlassChip(cornerRadius: CGFloat = 10) -> some View {
        modifier(LiquidGlassChipModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassGroup(spacing: CGFloat = 16) -> some View {
        modifier(LiquidGlassGroupModifier(spacing: spacing))
    }

    func liquidGlassButtonStyle(
        cornerRadius: CGFloat = 22,
        isSelected: Bool = false,
        minimumSize: CGSize? = nil,
        showsIdleSurface: Bool = true
    ) -> some View {
        buttonStyle(
            LiquidGlassButtonStyle(
                cornerRadius: cornerRadius,
                isSelected: isSelected,
                minimumSize: minimumSize,
                showsIdleSurface: showsIdleSurface
            )
        )
    }
}
