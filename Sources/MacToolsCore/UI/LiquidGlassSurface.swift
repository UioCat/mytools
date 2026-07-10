import AppKit
import SwiftUI

enum LiquidGlassTint: Equatable {
    case none
    case neutral(Double)
    case adaptiveGray(Double)
    case accent(Double)

    var color: Color? {
        switch self {
        case .none:
            return nil
        case .neutral(let opacity):
            return Color(nsColor: .windowBackgroundColor).opacity(opacity)
        case .adaptiveGray(let opacity):
            return Color.primary.opacity(opacity)
        case .accent(let opacity):
            return Color.accentColor.opacity(opacity)
        }
    }
}

enum LiquidGlassCornerShape: Equatable {
    case fixed(CGFloat)
    case concentric(minimum: CGFloat)

    var minimumRadius: CGFloat {
        switch self {
        case .fixed(let radius), .concentric(let radius):
            return radius
        }
    }
}

public enum LiquidGlassCornerGeometry {
    public static let windowRadius: CGFloat = 40
    public static let selectedRowMinimumRadius: CGFloat = 18
}

struct LiquidGlassSurfaceStyle {
    let cornerShape: LiquidGlassCornerShape
    let isInteractive: Bool
    let tint: LiquidGlassTint

    var cornerRadius: CGFloat {
        cornerShape.minimumRadius
    }

    static func panel(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: .none
        )
    }

    static func module(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: isSelected ? .neutral(0.32) : .neutral(0.10)
        )
    }

    static func concentricModule(minimumCornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .concentric(minimum: minimumCornerRadius),
            isInteractive: false,
            tint: isSelected ? .adaptiveGray(0.18) : .neutral(0.10)
        )
    }

    static func interactiveModule(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: true,
            tint: isSelected ? .accent(0.30) : .neutral(0.14)
        )
    }

    static func chip(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: .accent(0.08)
        )
    }

    var effect: Glass {
        let glass = tint.color.map { Glass.regular.tint($0) } ?? .regular
        return glass.interactive(isInteractive)
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(style: .panel(cornerRadius: cornerRadius))
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
        minWidth: 600,
        idealWidth: 720,
        maxWidth: .infinity,
        minHeight: 414,
        idealHeight: 480,
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
    let frame: LiquidGlassWindowPanelFrame

    func body(content: Content) -> some View {
        let windowShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

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
            .containerShape(windowShape)
            .clipShape(windowShape)
            .nativeLiquidGlassSurface(style: .panel(cornerRadius: cornerRadius))
            .contentShape(windowShape)
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

    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(style: style)
    }
}

struct LiquidGlassConcentricModuleModifier: ViewModifier {
    let minimumCornerRadius: CGFloat
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(
            style: .concentricModule(
                minimumCornerRadius: minimumCornerRadius,
                isSelected: isSelected
            )
        )
    }
}

struct LiquidGlassChipModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(style: .chip(cornerRadius: cornerRadius))
    }
}

struct LiquidGlassGroupModifier: ViewModifier {
    let spacing: CGFloat

    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

private extension View {
    @ViewBuilder
    func nativeLiquidGlassSurface(style: LiquidGlassSurfaceStyle) -> some View {
        switch style.cornerShape {
        case .fixed(let cornerRadius):
            glassEffect(
                style.effect,
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
        case .concentric(let minimumCornerRadius):
            glassEffect(
                style.effect,
                in: ConcentricRectangle(
                    corners: .concentric(minimum: .fixed(minimumCornerRadius)),
                    isUniform: true
                )
            )
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
        configuration.label
            .frame(
                minWidth: minimumSize?.width,
                minHeight: minimumSize?.height
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .modifier(
                NativeLiquidGlassButtonSurfaceModifier(
                    cornerRadius: cornerRadius,
                    isSelected: isSelected,
                    isPressed: configuration.isPressed,
                    showsIdleSurface: showsIdleSurface
                )
            )
    }
}

private struct NativeLiquidGlassButtonSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    let isPressed: Bool
    let showsIdleSurface: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsIdleSurface || isSelected || isPressed {
            content.nativeLiquidGlassSurface(
                style: .interactiveModule(
                    cornerRadius: cornerRadius,
                    isSelected: isSelected || isPressed
                )
            )
        } else {
            content
        }
    }
}

public extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 28) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassWindowPanel(
        cornerRadius: CGFloat = LiquidGlassCornerGeometry.windowRadius,
        frame: LiquidGlassWindowPanelFrame
    ) -> some View {
        modifier(
            LiquidGlassWindowPanelModifier(
                cornerRadius: cornerRadius,
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

    func liquidGlassConcentricModule(
        minimumCornerRadius: CGFloat = LiquidGlassCornerGeometry.selectedRowMinimumRadius,
        isSelected: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassConcentricModuleModifier(
                minimumCornerRadius: minimumCornerRadius,
                isSelected: isSelected
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
