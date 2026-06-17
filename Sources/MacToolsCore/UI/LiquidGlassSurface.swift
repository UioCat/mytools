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
            materialOpacity: 0.86,
            nativeBaseOpacity: 0.020,
            nativeTintOpacity: 0.075,
            legacyOverlayOpacity: 0.105,
            accentTintOpacity: 0,
            borderOpacity: 0.46,
            edgeDepthOpacity: 0.18,
            accentFocusOpacity: 0,
            highlightOpacity: 0.180,
            shadowOpacity: 0.24,
            shadowRadius: 32,
            shadowY: 16
        )
    }

    static func module(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: false,
            usesNativeGlassEffect: false,
            materialOpacity: isSelected ? 0.82 : 0.76,
            nativeBaseOpacity: isSelected ? 0.040 : 0.018,
            nativeTintOpacity: isSelected ? 0.120 : 0.055,
            legacyOverlayOpacity: isSelected ? 0.150 : 0.075,
            accentTintOpacity: isSelected ? 0.145 : 0.025,
            borderOpacity: isSelected ? 0.54 : 0.30,
            edgeDepthOpacity: isSelected ? 0.120 : 0.070,
            accentFocusOpacity: isSelected ? 0.58 : 0,
            highlightOpacity: isSelected ? 0.190 : 0.135,
            shadowOpacity: isSelected ? 0.16 : 0.08,
            shadowRadius: isSelected ? 14 : 8,
            shadowY: isSelected ? 7 : 4
        )
    }

    static func interactiveModule(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: true,
            usesNativeGlassEffect: false,
            materialOpacity: isSelected ? 0.86 : 0.78,
            nativeBaseOpacity: isSelected ? 0.045 : 0.022,
            nativeTintOpacity: isSelected ? 0.135 : 0.065,
            legacyOverlayOpacity: isSelected ? 0.165 : 0.085,
            accentTintOpacity: isSelected ? 0.175 : 0.030,
            borderOpacity: isSelected ? 0.58 : 0.34,
            edgeDepthOpacity: isSelected ? 0.130 : 0.075,
            accentFocusOpacity: isSelected ? 0.62 : 0,
            highlightOpacity: isSelected ? 0.205 : 0.145,
            shadowOpacity: isSelected ? 0.18 : 0.09,
            shadowRadius: isSelected ? 15 : 8,
            shadowY: isSelected ? 7 : 4
        )
    }

    static func chip(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerRadius: cornerRadius,
            isNativeGlassInteractive: false,
            usesNativeGlassEffect: false,
            materialOpacity: 0.72,
            nativeBaseOpacity: 0.012,
            nativeTintOpacity: 0.045,
            legacyOverlayOpacity: 0.060,
            accentTintOpacity: 0,
            borderOpacity: 0.24,
            edgeDepthOpacity: 0.035,
            accentFocusOpacity: 0,
            highlightOpacity: 0.100,
            shadowOpacity: 0.04,
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
            .background(MacToolsGlassTheme.windowBackground)
            .liquidGlassPanel(cornerRadius: cornerRadius)
            .clipShape(RoundedRectangle(cornerRadius: clipCornerRadius, style: .continuous))
            .environment(\.colorScheme, .light)
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
        content
    }
}

private extension View {
    @ViewBuilder
    @available(macOS 26.0, *)
    func nativeLiquidGlassSurface(style: LiquidGlassSurfaceStyle, material: NSVisualEffectView.Material) -> some View {
        self.legacyLiquidGlassSurface(style: style, material: material)
    }

    func legacyLiquidGlassSurface(style: LiquidGlassSurfaceStyle, material: NSVisualEffectView.Material) -> some View {
        self
            .compositingGroup()
            .background(
                ZStack {
                    VisualEffectBackground(material: material)
                        .opacity(style.materialOpacity)
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(MacToolsGlassTheme.panelTint.opacity(style.legacyOverlayOpacity))
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlAccentColor).opacity(style.accentTintOpacity))
                    surfaceHighlight(style: style)
                    liquidRefractionBands(style: style)
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

    func liquidRefractionBands(style: LiquidGlassSurfaceStyle) -> some View {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.00),
                        .init(color: Color.white.opacity(style.highlightOpacity * 0.26), location: 0.18),
                        .init(color: Color.clear, location: 0.34),
                        .init(color: Color(nsColor: .controlAccentColor).opacity(style.highlightOpacity * 0.18), location: 0.62),
                        .init(color: Color.clear, location: 0.84),
                        .init(color: Color.white.opacity(style.highlightOpacity * 0.16), location: 1.00)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
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

            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(style.borderOpacity * 0.78),
                            Color.clear,
                            Color.white.opacity(style.borderOpacity * 0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
                .blendMode(.screen)

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
