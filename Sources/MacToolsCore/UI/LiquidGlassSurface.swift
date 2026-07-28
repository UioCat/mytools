// `LiquidGlassSurface` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import AppKit
import SwiftUI

/// 描述 `LiquidGlassTint` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum LiquidGlassTint: Equatable {
    case none
    case neutral(Double)
    case adaptiveGray(Double)
    case frost(Double)
    case selection(Double)
    case accent(Double)

    var color: Color? {
        switch self {
        case .none:
            return nil
        case .neutral(let opacity):
            return Color(nsColor: .windowBackgroundColor).opacity(opacity)
        case .adaptiveGray(let opacity):
            return Color.primary.opacity(opacity)
        case .frost(let opacity):
            return Color.white.opacity(opacity)
        case .selection(let opacity):
            return MacToolsGlassTheme.selectionBlue.opacity(opacity)
        case .accent(let opacity):
            return Color.accentColor.opacity(opacity)
        }
    }
}

/// 描述 `LiquidGlassCornerShape` 在 SwiftUI 展示层中可取的状态、选项或错误。
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

/// 描述 `LiquidGlassCornerGeometry` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum LiquidGlassCornerGeometry {
    public static let windowRadius: CGFloat = 40
    public static let compactPanelRadius: CGFloat = 22
    public static let screenshotModeRadius: CGFloat = 16
    public static let screenshotToolbarRadius: CGFloat = 24
    public static let recordingControlRadius: CGFloat = 16
    public static let selectedRowMinimumRadius: CGFloat = 18
    public static let controlRadius: CGFloat = 14
    public static let smallControlRadius: CGFloat = 10
}

/// 描述统一工具界面中默认、悬停、选中和聚焦表面的展示状态。
public enum LiquidGlassInteractionState: Equatable, Sendable {
    case idle
    case hovered
    case selected
    case focused
}

/// 封装 `LiquidGlassSurfaceStyle` 在 SwiftUI 展示层中的值语义和相关操作。
struct LiquidGlassSurfaceStyle {
    let cornerShape: LiquidGlassCornerShape
    let isInteractive: Bool
    let tint: LiquidGlassTint
    let usesIdentityEffect: Bool

    private init(
        cornerShape: LiquidGlassCornerShape,
        isInteractive: Bool,
        tint: LiquidGlassTint,
        usesIdentityEffect: Bool = false
    ) {
        self.cornerShape = cornerShape
        self.isInteractive = isInteractive
        self.tint = tint
        self.usesIdentityEffect = usesIdentityEffect
    }

    var cornerRadius: CGFloat {
        cornerShape.minimumRadius
    }

    /// 构建并返回 `panel` 对应的 SwiftUI 界面内容或展示状态。
    static func panel(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: .none
        )
    }

    /// 构建不绘制表面的占位效果，保持交互期间的玻璃视图层级稳定。
    static func identity(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: .none,
            usesIdentityEffect: true
        )
    }

    /// 构建并返回 `module` 对应的 SwiftUI 界面内容或展示状态。
    static func module(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: isSelected ? .neutral(0.32) : .neutral(0.10)
        )
    }

    /// 构建并返回 `concentricModule` 对应的 SwiftUI 界面内容或展示状态。
    static func concentricModule(minimumCornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .concentric(minimum: minimumCornerRadius),
            isInteractive: isSelected,
            tint: isSelected ? .frost(0.22) : .neutral(0.10)
        )
    }

    /// 构建并返回 `floatingSelection` 对应的 SwiftUI 界面内容或展示状态。
    static func floatingSelection(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: true,
            tint: .selection(0.12)
        )
    }

    /// 构建中性悬停表面，避免把未选中的可点击内容误显示为蓝色焦点。
    static func hover(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: true,
            tint: .adaptiveGray(0.075)
        )
    }

    /// 构建并返回 `interactiveModule` 对应的 SwiftUI 界面内容或展示状态。
    static func interactiveModule(cornerRadius: CGFloat, isSelected: Bool) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: true,
            tint: isSelected ? .accent(0.30) : .neutral(0.14)
        )
    }

    /// 构建并返回 `chip` 对应的 SwiftUI 界面内容或展示状态。
    static func chip(cornerRadius: CGFloat) -> LiquidGlassSurfaceStyle {
        LiquidGlassSurfaceStyle(
            cornerShape: .fixed(cornerRadius),
            isInteractive: false,
            tint: .accent(0.08)
        )
    }

    var effect: Glass {
        if usesIdentityEffect {
            return .identity
        }

        let glass = tint.color.map { Glass.regular.tint($0) } ?? .regular
        return glass.interactive(isInteractive)
    }
}

/// 封装 `LiquidGlassPanelModifier` 在 SwiftUI 展示层中的值语义和相关操作。
struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(style: .panel(cornerRadius: cornerRadius))
    }
}

/// 描述 `LiquidGlassWindowPanelSurfacePlacement` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum LiquidGlassWindowPanelSurfacePlacement: Equatable, Sendable {
    case afterSizing
}

/// 描述 `LiquidGlassWindowPanelAlignment` 在 SwiftUI 展示层中可取的状态、选项或错误。
public enum LiquidGlassWindowPanelAlignment: Equatable, Sendable {
    case topLeading

    var swiftUIAlignment: Alignment {
        switch self {
        case .topLeading:
            return .topLeading
        }
    }
}

/// 封装 `LiquidGlassWindowPanelFrame` 在 SwiftUI 展示层中的值语义和相关操作。
public struct LiquidGlassWindowPanelFrame: Equatable, Sendable {
    public let minWidth: CGFloat
    public let idealWidth: CGFloat
    public let maxWidth: CGFloat
    public let minHeight: CGFloat
    public let idealHeight: CGFloat
    public let maxHeight: CGFloat
    public let alignment: LiquidGlassWindowPanelAlignment
    public var surfacePlacement: LiquidGlassWindowPanelSurfacePlacement { .afterSizing }

    /// 创建 `LiquidGlassWindowPanelFrame`，保存传入依赖并建立初始状态。
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

/// 封装 `LiquidGlassWindowPanelModifier` 在 SwiftUI 展示层中的值语义和相关操作。
private struct LiquidGlassWindowPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let frame: LiquidGlassWindowPanelFrame

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
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

/// 封装 `LiquidGlassModuleModifier` 在 SwiftUI 展示层中的值语义和相关操作。
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

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(style: style)
    }
}

/// 封装 `LiquidGlassConcentricModuleModifier` 在 SwiftUI 展示层中的值语义和相关操作。
struct LiquidGlassConcentricModuleModifier: ViewModifier {
    let minimumCornerRadius: CGFloat
    let isSelected: Bool

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        let shape = ConcentricRectangle(
            corners: .concentric(minimum: .fixed(minimumCornerRadius)),
            isUniform: true
        )

        content.nativeLiquidGlassSurface(
            style: .concentricModule(
                minimumCornerRadius: minimumCornerRadius,
                isSelected: isSelected
            )
        )
        .overlay {
            if isSelected {
                shape
                    .stroke(Color.white.opacity(0.36), lineWidth: 1.5)
                shape
                    .stroke(MacToolsGlassTheme.selectionBlue.opacity(0.30), lineWidth: 0.75)
            }
        }
        .shadow(
            color: Color.black.opacity(isSelected ? 0.14 : 0),
            radius: isSelected ? 14 : 0,
            x: 0,
            y: isSelected ? 6 : 0
        )
        .shadow(
            color: Color.black.opacity(isSelected ? 0.055 : 0),
            radius: isSelected ? 3 : 0,
            x: 0,
            y: isSelected ? 1 : 0
        )
    }
}

/// 封装 `LiquidGlassFloatingSelectionModifier` 在 SwiftUI 展示层中的值语义和相关操作。
struct LiquidGlassFloatingSelectionModifier: ViewModifier {
    let cornerRadius: CGFloat

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .nativeLiquidGlassSurface(style: .floatingSelection(cornerRadius: cornerRadius))
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.30), lineWidth: 1.25)
                shape
                    .stroke(MacToolsGlassTheme.selectionBlue.opacity(0.24), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

/// 将统一交互状态映射到稳定的 Liquid Glass 节点和语义表面。
private struct LiquidGlassInteractionSurfaceModifier: ViewModifier {
    let state: LiquidGlassInteractionState
    let cornerRadius: CGFloat

    private var style: LiquidGlassSurfaceStyle {
        switch state {
        case .idle:
            return .identity(cornerRadius: cornerRadius)
        case .hovered:
            return .hover(cornerRadius: cornerRadius)
        case .selected, .focused:
            return .floatingSelection(cornerRadius: cornerRadius)
        }
    }

    func body(content: Content) -> some View {
        content
            .nativeLiquidGlassSurface(style: style)
            .overlay {
                if state == .selected || state == .focused {
                    let shape = RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    shape
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    shape
                        .stroke(
                            state == .focused
                                ? MacToolsGlassTheme.focusBorder
                                : MacToolsGlassTheme.selectionBorder,
                            lineWidth: state == .focused ? 1.25 : 0.75
                        )
                }
        }
    }
}

/// 封装 `LiquidGlassChipModifier` 在 SwiftUI 展示层中的值语义和相关操作。
struct LiquidGlassChipModifier: ViewModifier {
    let cornerRadius: CGFloat

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        content.nativeLiquidGlassSurface(style: .chip(cornerRadius: cornerRadius))
    }
}

/// 封装 `LiquidGlassGroupModifier` 在 SwiftUI 展示层中的值语义和相关操作。
struct LiquidGlassGroupModifier: ViewModifier {
    let spacing: CGFloat

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

/// 扩展 `View`，补充本文件所需的 SwiftUI 展示层能力。
private extension View {
    /// 构建并返回 `nativeLiquidGlassSurface` 对应的 SwiftUI 界面内容或展示状态。
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

/// 封装 `LiquidGlassButtonStyle` 在 SwiftUI 展示层中的值语义和相关操作。
public struct LiquidGlassButtonStyle: ButtonStyle {
    private let cornerRadius: CGFloat
    private let isSelected: Bool
    private let minimumSize: CGSize?
    private let showsIdleSurface: Bool

    /// 创建 `LiquidGlassButtonStyle`，保存传入依赖并建立初始状态。
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

    /// 构造并返回 `makeBody` 所描述的 SwiftUI 展示层对象。
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

/// 封装 `NativeLiquidGlassButtonSurfaceModifier` 在 SwiftUI 展示层中的值语义和相关操作。
private struct NativeLiquidGlassButtonSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isSelected: Bool
    let isPressed: Bool
    let showsIdleSurface: Bool

    /// 构建并返回 `body` 对应的 SwiftUI 界面内容或展示状态。
    func body(content: Content) -> some View {
        let style: LiquidGlassSurfaceStyle
        if isSelected || isPressed {
            style = .floatingSelection(cornerRadius: cornerRadius)
        } else if showsIdleSurface {
            style = .interactiveModule(
                cornerRadius: cornerRadius,
                isSelected: false
            )
        } else {
            style = .identity(cornerRadius: cornerRadius)
        }

        return content.nativeLiquidGlassSurface(style: style)
    }
}

/// 扩展 `View`，补充本文件所需的 SwiftUI 展示层能力。
public extension View {
    /// 构建并返回 `liquidGlassPanel` 对应的 SwiftUI 界面内容或展示状态。
    func liquidGlassPanel(cornerRadius: CGFloat = 28) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }

    /// 构建并返回 `liquidGlassWindowPanel` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `liquidGlassModule` 对应的 SwiftUI 界面内容或展示状态。
    func liquidGlassModule(cornerRadius: CGFloat = 22, isSelected: Bool = false) -> some View {
        modifier(
            LiquidGlassModuleModifier(
                cornerRadius: cornerRadius,
                isSelected: isSelected,
                isInteractive: false
            )
        )
    }

    /// 构建并返回 `liquidGlassConcentricModule` 对应的 SwiftUI 界面内容或展示状态。
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

    /// 构建并返回 `liquidGlassFloatingSelection` 对应的 SwiftUI 界面内容或展示状态。
    func liquidGlassFloatingSelection(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassFloatingSelectionModifier(cornerRadius: cornerRadius))
    }

    /// 应用统一的默认、悬停、选中或聚焦表面，同时保持玻璃节点层级稳定。
    func liquidGlassInteractionSurface(
        state: LiquidGlassInteractionState,
        cornerRadius: CGFloat = LiquidGlassCornerGeometry.controlRadius
    ) -> some View {
        modifier(
            LiquidGlassInteractionSurfaceModifier(
                state: state,
                cornerRadius: cornerRadius
            )
        )
    }

    /// 构建并返回 `liquidGlassInteractiveModule` 对应的 SwiftUI 界面内容或展示状态。
    func liquidGlassInteractiveModule(cornerRadius: CGFloat = 22, isSelected: Bool = false) -> some View {
        modifier(
            LiquidGlassModuleModifier(
                cornerRadius: cornerRadius,
                isSelected: isSelected,
                isInteractive: true
            )
        )
    }

    /// 构建并返回 `liquidGlassChip` 对应的 SwiftUI 界面内容或展示状态。
    func liquidGlassChip(cornerRadius: CGFloat = 10) -> some View {
        modifier(LiquidGlassChipModifier(cornerRadius: cornerRadius))
    }

    /// 构建并返回 `liquidGlassGroup` 对应的 SwiftUI 界面内容或展示状态。
    func liquidGlassGroup(spacing: CGFloat = 16) -> some View {
        modifier(LiquidGlassGroupModifier(spacing: spacing))
    }

    /// 构建并返回 `liquidGlassButtonStyle` 对应的 SwiftUI 界面内容或展示状态。
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
