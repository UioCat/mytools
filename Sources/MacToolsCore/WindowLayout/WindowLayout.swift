// `WindowLayout` 的窗口布局领域实现。
// 负责布局模式、几何计算和快捷键配置，不直接写入辅助功能窗口属性。

import CoreGraphics
import Foundation

/// 封装 `WindowLayoutPreviewSegment` 在窗口布局领域中的值语义和相关操作。
public struct WindowLayoutPreviewSegment: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    /// 创建 `WindowLayoutPreviewSegment`，保存传入依赖并建立初始状态。
    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 描述 `WindowLayoutMode` 在窗口布局领域中可取的状态、选项或错误。
public enum WindowLayoutMode: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case centered
    case maximize

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf:
            return "左半屏"
        case .rightHalf:
            return "右半屏"
        case .topHalf:
            return "上半屏"
        case .bottomHalf:
            return "下半屏"
        case .leftThird:
            return "左 1/3"
        case .rightThird:
            return "右 1/3"
        case .leftTwoThirds:
            return "左 2/3"
        case .rightTwoThirds:
            return "右 2/3"
        case .centered:
            return "居中"
        case .maximize:
            return "满屏"
        }
    }

    public var systemImage: String {
        switch self {
        case .leftHalf, .leftThird, .leftTwoThirds:
            return "rectangle.lefthalf.filled"
        case .rightHalf, .rightThird, .rightTwoThirds:
            return "rectangle.righthalf.filled"
        case .topHalf:
            return "rectangle.tophalf.filled"
        case .bottomHalf:
            return "rectangle.bottomhalf.filled"
        case .centered:
            return "rectangle.center.inset.filled"
        case .maximize:
            return "arrow.up.left.and.arrow.down.right"
        }
    }

    public var previewSegment: WindowLayoutPreviewSegment {
        switch self {
        case .leftHalf:
            return .init(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf:
            return .init(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf:
            return .init(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf:
            return .init(x: 0, y: 0.5, width: 1, height: 0.5)
        case .leftThird:
            return .init(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
        case .rightThird:
            return .init(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
        case .leftTwoThirds:
            return .init(x: 0, y: 0, width: 2.0 / 3.0, height: 1)
        case .rightTwoThirds:
            return .init(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1)
        case .centered:
            return .init(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        case .maximize:
            return .init(x: 0, y: 0, width: 1, height: 1)
        }
    }
}

/// 封装 `WindowLayoutButton` 在窗口布局领域中的值语义和相关操作。
public struct WindowLayoutButton: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var modes: [WindowLayoutMode]

    /// 创建 `WindowLayoutButton`，保存传入依赖并建立初始状态。
    public init(id: String, title: String, modes: [WindowLayoutMode]) {
        self.id = id
        self.title = title
        self.modes = Self.uniqueModes(modes)
    }

    /// 创建 `WindowLayoutButton`，保存传入依赖并建立初始状态。
    public init(mode: WindowLayoutMode) {
        self.init(id: "mode.\(mode.rawValue)", title: mode.title, modes: [mode])
    }

    public var systemImage: String {
        if modes.count == 1, let mode = modes.first {
            return mode.systemImage
        }
        return "rectangle.3.group"
    }

    public var modeSummary: String {
        modes.map(\.title).joined(separator: " / ")
    }

    /// 计算并返回 `mode` 对应的窗口布局领域数据或状态结果。
    public func mode(after previousMode: WindowLayoutMode?) -> WindowLayoutMode? {
        guard !modes.isEmpty else {
            return nil
        }

        guard
            let previousMode,
            let previousIndex = modes.firstIndex(of: previousMode)
        else {
            return modes.first
        }

        let nextIndex = modes.index(after: previousIndex)
        return nextIndex == modes.endIndex ? modes.first : modes[nextIndex]
    }

    /// 计算并返回 `uniqueModes` 对应的窗口布局领域数据或状态结果。
    static func uniqueModes(_ modes: [WindowLayoutMode]) -> [WindowLayoutMode] {
        var seen = Set<WindowLayoutMode>()
        return modes.filter { seen.insert($0).inserted }
    }
}

/// 封装 `WindowLayoutModeShortcuts` 在窗口布局领域中的值语义和相关操作。
public struct WindowLayoutModeShortcuts: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var mode: WindowLayoutMode
    public var shortcuts: [HotKeyBinding]

    public var id: WindowLayoutMode { mode }

    /// 创建 `WindowLayoutModeShortcuts`，保存传入依赖并建立初始状态。
    public init(mode: WindowLayoutMode, shortcuts: [HotKeyBinding]) {
        self.mode = mode
        self.shortcuts = Self.uniqueShortcuts(shortcuts)
    }

    /// 计算并返回 `uniqueShortcuts` 对应的窗口布局领域数据或状态结果。
    static func uniqueShortcuts(_ shortcuts: [HotKeyBinding]) -> [HotKeyBinding] {
        var seen = Set<HotKeyBinding>()
        return shortcuts.filter { shortcut in
            shortcut.isUsableGlobalShortcut && seen.insert(shortcut).inserted
        }
    }
}

/// 封装 `WindowLayoutModeGroup` 在窗口布局领域中的值语义和相关操作。
struct WindowLayoutModeGroup: Equatable, Identifiable, Sendable {
    var title: String
    var modes: [WindowLayoutMode]

    var id: String { title }
}

/// 描述 `WindowLayoutSettingsLayout` 在窗口布局领域中可取的状态、选项或错误。
enum WindowLayoutSettingsLayout {
    static let modeGroups: [WindowLayoutModeGroup] = [
        WindowLayoutModeGroup(title: "水平半屏", modes: [.leftHalf, .rightHalf]),
        WindowLayoutModeGroup(title: "垂直半屏", modes: [.topHalf, .bottomHalf]),
        WindowLayoutModeGroup(title: "三分之一", modes: [.leftThird, .rightThird]),
        WindowLayoutModeGroup(title: "三分之二", modes: [.leftTwoThirds, .rightTwoThirds]),
        WindowLayoutModeGroup(title: "焦点", modes: [.centered, .maximize])
    ]
}

/// 封装 `WindowLayoutSettings` 在窗口布局领域中的值语义和相关操作。
public struct WindowLayoutSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var enabledModes: [WindowLayoutMode]
    public var customButtons: [WindowLayoutButton]
    public var modeShortcuts: [WindowLayoutModeShortcuts]

    public static let defaultModeShortcuts: [WindowLayoutModeShortcuts] = [
        WindowLayoutModeShortcuts(
            mode: .leftHalf,
            shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Control", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .rightHalf,
            shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Control", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .topHalf,
            shortcuts: [HotKeyBinding(key: "Up", modifiers: ["Control", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .bottomHalf,
            shortcuts: [HotKeyBinding(key: "Down", modifiers: ["Control", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .leftThird,
            shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Control", "Option"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .rightThird,
            shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Control", "Option"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .leftTwoThirds,
            shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Option", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .rightTwoThirds,
            shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Option", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .centered,
            shortcuts: [HotKeyBinding(key: "0", modifiers: ["Control", "Option"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .maximize,
            shortcuts: [HotKeyBinding(key: "0", modifiers: ["Control", "Command"])]
        )
    ]

    public static let defaults = WindowLayoutSettings(modeShortcuts: defaultModeShortcuts)

    /// 创建 `WindowLayoutSettings`，保存传入依赖并建立初始状态。
    public init(
        isEnabled: Bool = true,
        enabledModes: [WindowLayoutMode] = WindowLayoutMode.allCases,
        customButtons: [WindowLayoutButton] = [],
        modeShortcuts: [WindowLayoutModeShortcuts] = []
    ) {
        self.isEnabled = isEnabled
        self.enabledModes = WindowLayoutButton.uniqueModes(enabledModes)
        self.customButtons = Self.normalizedCustomButtons(customButtons)
        self.modeShortcuts = Self.normalizedModeShortcuts(modeShortcuts)
    }

    public var visibleButtons: [WindowLayoutButton] {
        guard isEnabled else {
            return []
        }

        return enabledModes.map(WindowLayoutButton.init(mode:))
    }

    public var shortcutBindings: [(mode: WindowLayoutMode, binding: HotKeyBinding)] {
        guard isEnabled else {
            return []
        }

        var seen = Set<HotKeyBinding>()
        return WindowLayoutMode.allCases.flatMap { mode in
            shortcuts(for: mode).compactMap { binding in
                guard seen.insert(binding).inserted else {
                    return nil
                }
                return (mode, binding)
            }
        }
    }

    /// 计算并返回 `shortcuts` 对应的窗口布局领域数据或状态结果。
    public func shortcuts(for mode: WindowLayoutMode) -> [HotKeyBinding] {
        modeShortcuts.first { $0.mode == mode }?.shortcuts ?? []
    }

    /// 按照字段时钟或配置优先级计算 `replacingPrimaryShortcut` 对应的窗口布局领域合并结果。
    public func replacingPrimaryShortcut(
        for mode: WindowLayoutMode,
        with shortcut: HotKeyBinding?
    ) -> WindowLayoutSettings {
        var updatedModeShortcuts = modeShortcuts.filter { $0.mode != mode }
        if let shortcut, shortcut.isUsableGlobalShortcut {
            updatedModeShortcuts.append(WindowLayoutModeShortcuts(mode: mode, shortcuts: [shortcut]))
        }

        return WindowLayoutSettings(
            isEnabled: isEnabled,
            enabledModes: enabledModes,
            customButtons: customButtons,
            modeShortcuts: updatedModeShortcuts
        )
    }

    /// 按照字段时钟或配置优先级计算 `updatingPanelConfiguration` 对应的窗口布局领域合并结果。
    public func updatingPanelConfiguration(
        isEnabled: Bool,
        enabledModes: Set<WindowLayoutMode>,
        customButtons: [WindowLayoutButton]? = nil,
        modeShortcuts: [WindowLayoutModeShortcuts]
    ) -> WindowLayoutSettings {
        WindowLayoutSettings(
            isEnabled: isEnabled,
            enabledModes: WindowLayoutMode.allCases.filter { enabledModes.contains($0) },
            customButtons: customButtons ?? self.customButtons,
            modeShortcuts: modeShortcuts
        )
    }

    /// 描述 `CodingKeys` 在窗口布局领域中可取的状态、选项或错误。
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case enabledModes
        case customButtons
        case modeShortcuts
    }

    /// 创建 `WindowLayoutSettings`，保存传入依赖并建立初始状态。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEnabledModes = try container.decodeIfPresent(
            [WindowLayoutMode].self,
            forKey: .enabledModes
        ) ?? WindowLayoutMode.allCases
        let decodedModeShortcuts = try container.decodeIfPresent(
            [WindowLayoutModeShortcuts].self,
            forKey: .modeShortcuts
        ) ?? []
        let decodedCustomButtons = try container.decodeIfPresent(
            [WindowLayoutButton].self,
            forKey: .customButtons
        ) ?? []
        let shouldMigrateLegacyDefaults = decodedEnabledModes == Self.legacyDefaultModes
            && Self.normalizedModeShortcuts(decodedModeShortcuts)
                == Self.legacyDefaultModeShortcuts
            && decodedCustomButtons.isEmpty
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            enabledModes: shouldMigrateLegacyDefaults
                ? WindowLayoutMode.allCases
                : decodedEnabledModes,
            customButtons: decodedCustomButtons,
            modeShortcuts: shouldMigrateLegacyDefaults
                ? Self.defaultModeShortcuts
                : decodedModeShortcuts
        )
    }

    /// 转换 `encode` 接收的窗口布局领域数据，并返回规范化结果。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(enabledModes, forKey: .enabledModes)
        try container.encode(customButtons, forKey: .customButtons)
        try container.encode(modeShortcuts, forKey: .modeShortcuts)
    }

    /// 转换 `normalizedCustomButtons` 接收的窗口布局领域数据，并返回规范化结果。
    private static func normalizedCustomButtons(_ buttons: [WindowLayoutButton]) -> [WindowLayoutButton] {
        var seen = Set<String>()
        return buttons.compactMap { button in
            let id = button.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else {
                return nil
            }

            let modes = WindowLayoutButton.uniqueModes(button.modes)
            guard !modes.isEmpty else {
                return nil
            }

            let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return WindowLayoutButton(
                id: id,
                title: title.isEmpty ? modes.map(\.title).joined(separator: " / ") : title,
                modes: modes
            )
        }
    }

    /// 转换 `normalizedModeShortcuts` 接收的窗口布局领域数据，并返回规范化结果。
    private static func normalizedModeShortcuts(
        _ modeShortcuts: [WindowLayoutModeShortcuts]
    ) -> [WindowLayoutModeShortcuts] {
        var shortcutsByMode: [WindowLayoutMode: [HotKeyBinding]] = [:]
        for modeShortcut in modeShortcuts {
            shortcutsByMode[modeShortcut.mode, default: []].append(contentsOf: modeShortcut.shortcuts)
        }

        return WindowLayoutMode.allCases.compactMap { mode in
            let shortcuts = WindowLayoutModeShortcuts.uniqueShortcuts(shortcutsByMode[mode] ?? [])
            guard !shortcuts.isEmpty else {
                return nil
            }
            return WindowLayoutModeShortcuts(mode: mode, shortcuts: shortcuts)
        }
    }

    private static let legacyDefaultModes: [WindowLayoutMode] = [
        .leftHalf,
        .rightHalf,
        .leftThird,
        .rightThird,
        .leftTwoThirds,
        .rightTwoThirds,
        .centered,
        .maximize
    ]

    private static let legacyDefaultModeShortcuts: [WindowLayoutModeShortcuts] = [
        WindowLayoutModeShortcuts(
            mode: .leftHalf,
            shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Control", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .rightHalf,
            shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Control", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .leftThird,
            shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Control", "Option"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .rightThird,
            shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Control", "Option"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .leftTwoThirds,
            shortcuts: [HotKeyBinding(key: "Left", modifiers: ["Option", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .rightTwoThirds,
            shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Option", "Command"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .centered,
            shortcuts: [HotKeyBinding(key: "0", modifiers: ["Control", "Option"])]
        ),
        WindowLayoutModeShortcuts(
            mode: .maximize,
            shortcuts: [HotKeyBinding(key: "0", modifiers: ["Control", "Command"])]
        )
    ]
}

/// 描述 `WindowLayoutCalculator` 在窗口布局领域中可取的状态、选项或错误。
public enum WindowLayoutCalculator {
    public static let centeredScale: CGFloat = 0.8

    /// 计算并返回 `targetFrame` 对应的窗口布局领域数据或状态结果。
    public static func targetFrame(for mode: WindowLayoutMode, in visibleFrame: CGRect) -> CGRect {
        switch mode {
        case .leftHalf:
            return leadingFrame(widthFraction: 0.5, in: visibleFrame)
        case .rightHalf:
            return trailingFrame(widthFraction: 0.5, in: visibleFrame)
        case .topHalf:
            return upperFrame(heightFraction: 0.5, in: visibleFrame)
        case .bottomHalf:
            return lowerFrame(heightFraction: 0.5, in: visibleFrame)
        case .leftThird:
            return leadingFrame(widthFraction: 1.0 / 3.0, in: visibleFrame)
        case .rightThird:
            return trailingFrame(widthFraction: 1.0 / 3.0, in: visibleFrame)
        case .leftTwoThirds:
            return leadingFrame(widthFraction: 2.0 / 3.0, in: visibleFrame)
        case .rightTwoThirds:
            return trailingFrame(widthFraction: 2.0 / 3.0, in: visibleFrame)
        case .centered:
            return centeredFrame(in: visibleFrame)
        case .maximize:
            return visibleFrame
        }
    }

    /// 计算并返回 `leadingFrame` 对应的窗口布局领域数据或状态结果。
    private static func leadingFrame(widthFraction: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var frame = visibleFrame
        frame.size.width = floor(visibleFrame.width * widthFraction)
        return frame
    }

    /// 计算并返回 `trailingFrame` 对应的窗口布局领域数据或状态结果。
    private static func trailingFrame(widthFraction: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var frame = leadingFrame(widthFraction: widthFraction, in: visibleFrame)
        frame.origin.x = visibleFrame.maxX - frame.width
        return frame
    }

    /// 计算并返回贴近可用区域上边缘的高度分区。
    private static func upperFrame(heightFraction: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var frame = lowerFrame(heightFraction: heightFraction, in: visibleFrame)
        frame.origin.y = visibleFrame.maxY - frame.height
        return frame
    }

    /// 计算并返回贴近可用区域下边缘的高度分区。
    private static func lowerFrame(heightFraction: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var frame = visibleFrame
        frame.size.height = floor(visibleFrame.height * heightFraction)
        return frame
    }

    /// 计算并返回 `centeredFrame` 对应的窗口布局领域数据或状态结果。
    private static func centeredFrame(in visibleFrame: CGRect) -> CGRect {
        let width = floor(visibleFrame.width * centeredScale)
        let height = floor(visibleFrame.height * centeredScale)
        return CGRect(
            x: round((visibleFrame.width - width) / 2.0) + visibleFrame.minX,
            y: round((visibleFrame.height - height) / 2.0) + visibleFrame.minY,
            width: width,
            height: height
        )
    }
}

/// 描述窗口布局重复执行时可查找的物理屏幕方向。
public enum WindowLayoutDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down
}

/// 使用纯几何数据描述一个可参与窗口布局的显示器。
public struct WindowLayoutScreen: Equatable, Sendable {
    public var id: String
    public var frame: CGRect
    public var visibleFrame: CGRect

    public init(id: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// 描述布局请求解析出的最终显示器、模式和目标矩形。
public struct WindowLayoutTarget: Equatable, Sendable {
    public var screen: WindowLayoutScreen
    public var mode: WindowLayoutMode
    public var frame: CGRect

    public init(screen: WindowLayoutScreen, mode: WindowLayoutMode, frame: CGRect) {
        self.screen = screen
        self.mode = mode
        self.frame = frame
    }
}

/// 根据上次成功布局和显示器物理位置解析重复方向动作。
public enum WindowScreenNavigationPolicy {
    public static func target(
        requestedMode: WindowLayoutMode,
        currentFrame: CGRect,
        previousMode: WindowLayoutMode?,
        previousTargetFrame: CGRect?,
        currentScreen: WindowLayoutScreen,
        screens: [WindowLayoutScreen],
        allowsTraversal: Bool = true
    ) -> WindowLayoutTarget {
        let currentTarget = WindowLayoutCalculator.targetFrame(
            for: requestedMode,
            in: currentScreen.visibleFrame
        )
        guard
            allowsTraversal,
            previousMode == requestedMode,
            let previousTargetFrame,
            WindowFrameApplicationPolicy.isSatisfied(
                actual: currentFrame,
                target: previousTargetFrame
            ),
            let traversal = requestedMode.directionalTraversal,
            let destinationScreen = adjacentScreen(
                from: currentScreen,
                direction: traversal.direction,
                screens: screens
            )
        else {
            return WindowLayoutTarget(
                screen: currentScreen,
                mode: requestedMode,
                frame: currentTarget
            )
        }

        return WindowLayoutTarget(
            screen: destinationScreen,
            mode: traversal.destinationMode,
            frame: WindowLayoutCalculator.targetFrame(
                for: traversal.destinationMode,
                in: destinationScreen.visibleFrame
            )
        )
    }

    /// 查找指定物理方向上最接近当前显示器的候选显示器。
    public static func adjacentScreen(
        from currentScreen: WindowLayoutScreen,
        direction: WindowLayoutDirection,
        screens: [WindowLayoutScreen]
    ) -> WindowLayoutScreen? {
        screens
            .filter { screen in
                screen.id != currentScreen.id
                    && isInDirection(screen.frame, from: currentScreen.frame, direction: direction)
            }
            .min { lhs, rhs in
                isPreferred(
                    lhs,
                    over: rhs,
                    from: currentScreen,
                    direction: direction
                )
            }
    }

    private static func isInDirection(
        _ candidate: CGRect,
        from current: CGRect,
        direction: WindowLayoutDirection
    ) -> Bool {
        switch direction {
        case .left:
            return candidate.midX < current.midX
        case .right:
            return candidate.midX > current.midX
        case .up:
            return candidate.midY > current.midY
        case .down:
            return candidate.midY < current.midY
        }
    }

    private static func isPreferred(
        _ lhs: WindowLayoutScreen,
        over rhs: WindowLayoutScreen,
        from current: WindowLayoutScreen,
        direction: WindowLayoutDirection
    ) -> Bool {
        let lhsScore = score(for: lhs, from: current, direction: direction)
        let rhsScore = score(for: rhs, from: current, direction: direction)
        if lhsScore.overlapRank != rhsScore.overlapRank {
            return lhsScore.overlapRank < rhsScore.overlapRank
        }
        if lhsScore.forwardGap != rhsScore.forwardGap {
            return lhsScore.forwardGap < rhsScore.forwardGap
        }
        if lhsScore.orthogonalCenterDistance != rhsScore.orthogonalCenterDistance {
            return lhsScore.orthogonalCenterDistance < rhsScore.orthogonalCenterDistance
        }
        return lhs.id < rhs.id
    }

    private static func score(
        for candidate: WindowLayoutScreen,
        from current: WindowLayoutScreen,
        direction: WindowLayoutDirection
    ) -> (overlapRank: Int, forwardGap: CGFloat, orthogonalCenterDistance: CGFloat) {
        switch direction {
        case .left:
            return (
                intervalGap(candidate.frame.minY...candidate.frame.maxY, current.frame.minY...current.frame.maxY) == 0 ? 0 : 1,
                max(0, current.frame.minX - candidate.frame.maxX),
                abs(candidate.frame.midY - current.frame.midY)
            )
        case .right:
            return (
                intervalGap(candidate.frame.minY...candidate.frame.maxY, current.frame.minY...current.frame.maxY) == 0 ? 0 : 1,
                max(0, candidate.frame.minX - current.frame.maxX),
                abs(candidate.frame.midY - current.frame.midY)
            )
        case .up:
            return (
                intervalGap(candidate.frame.minX...candidate.frame.maxX, current.frame.minX...current.frame.maxX) == 0 ? 0 : 1,
                max(0, candidate.frame.minY - current.frame.maxY),
                abs(candidate.frame.midX - current.frame.midX)
            )
        case .down:
            return (
                intervalGap(candidate.frame.minX...candidate.frame.maxX, current.frame.minX...current.frame.maxX) == 0 ? 0 : 1,
                max(0, current.frame.minY - candidate.frame.maxY),
                abs(candidate.frame.midX - current.frame.midX)
            )
        }
    }

    private static func intervalGap(
        _ lhs: ClosedRange<CGFloat>,
        _ rhs: ClosedRange<CGFloat>
    ) -> CGFloat {
        if lhs.overlaps(rhs) {
            return 0
        }
        return lhs.upperBound < rhs.lowerBound
            ? rhs.lowerBound - lhs.upperBound
            : lhs.lowerBound - rhs.upperBound
    }
}

private extension WindowLayoutMode {
    var directionalTraversal: (direction: WindowLayoutDirection, destinationMode: WindowLayoutMode)? {
        switch self {
        case .leftHalf:
            return (.left, .rightHalf)
        case .rightHalf:
            return (.right, .leftHalf)
        case .topHalf:
            return (.up, .bottomHalf)
        case .bottomHalf:
            return (.down, .topHalf)
        case .leftThird:
            return (.left, .rightThird)
        case .rightThird:
            return (.right, .leftThird)
        case .leftTwoThirds:
            return (.left, .rightTwoThirds)
        case .rightTwoThirds:
            return (.right, .leftTwoThirds)
        case .centered, .maximize:
            return nil
        }
    }
}

/// 描述窗口矩形中可独立写入和校验的属性。
public struct WindowFrameComponents: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let position = WindowFrameComponents(rawValue: 1 << 0)
    public static let size = WindowFrameComponents(rawValue: 1 << 1)
    public static let all: WindowFrameComponents = [.position, .size]
}

/// 描述一次辅助功能窗口属性写入。
public enum WindowFrameMutation: Equatable, Sendable {
    case position(CGPoint)
    case size(CGSize)
}

/// 定义窗口布局写入后的几何校验、写入顺序与有限重试策略。
public enum WindowFrameApplicationPolicy {
    public static let maximumWriteAttempts = 5
    public static let verificationTimeout: TimeInterval = 0.5
    public static let frameTolerance: CGFloat = 1
    private static let verificationDelays: [TimeInterval] = [0.016, 0.025, 0.05, 0.1, 0.15]

    /// 分别判断实际位置和尺寸是否达到目标；无法读取的属性保持为待处理状态。
    public static func mismatchedComponents(
        actualPosition: CGPoint?,
        actualSize: CGSize?,
        target: CGRect,
        tolerance: CGFloat = frameTolerance
    ) -> WindowFrameComponents {
        guard isValid(frame: target), tolerance >= 0 else {
            return .all
        }

        var result: WindowFrameComponents = []
        if
            actualPosition?.x.isFinite != true
                || actualPosition?.y.isFinite != true
                || abs((actualPosition?.x ?? .infinity) - target.origin.x) > tolerance
                || abs((actualPosition?.y ?? .infinity) - target.origin.y) > tolerance
        {
            result.insert(.position)
        }
        if
            actualSize?.width.isFinite != true
                || actualSize?.height.isFinite != true
                || (actualSize?.width ?? -1) < 0
                || (actualSize?.height ?? -1) < 0
                || abs((actualSize?.width ?? .infinity) - target.width) > tolerance
                || abs((actualSize?.height ?? .infinity) - target.height) > tolerance
        {
            result.insert(.size)
        }
        return result
    }

    /// 按实际尺寸变化方向生成写入计划，并只包含仍未到位的属性。
    public static func mutationPlan(
        current: CGRect,
        target: CGRect,
        components: WindowFrameComponents,
        isInitialCrossDisplayWrite: Bool = false,
        tolerance: CGFloat = frameTolerance
    ) -> [WindowFrameMutation] {
        guard isValid(frame: target), tolerance >= 0, !components.isEmpty else {
            return []
        }
        if components == .position {
            return [.position(target.origin)]
        }
        if components == .size {
            return [.size(target.size)]
        }
        if isInitialCrossDisplayWrite {
            return [.size(target.size), .position(target.origin), .size(target.size)]
        }
        guard isValid(frame: current) else {
            return [.position(target.origin), .size(target.size)]
        }

        let grows = target.width > current.width + tolerance
            || target.height > current.height + tolerance
        let shrinks = target.width < current.width - tolerance
            || target.height < current.height - tolerance

        if grows && shrinks {
            let intermediateSize = CGSize(
                width: min(current.width, target.width),
                height: min(current.height, target.height)
            )
            return [
                .size(intermediateSize),
                .position(target.origin),
                .size(target.size)
            ]
        }
        if shrinks {
            return [.size(target.size), .position(target.origin)]
        }
        return [.position(target.origin), .size(target.size)]
    }

    /// 判断系统回读的窗口矩形是否已经达到目标，允许不超过一个点的舍入差异。
    public static func isSatisfied(
        actual: CGRect,
        target: CGRect,
        tolerance: CGFloat = frameTolerance
    ) -> Bool {
        mismatchedComponents(
            actualPosition: actual.origin,
            actualSize: actual.size,
            target: target,
            tolerance: tolerance
        ).isEmpty
    }

    /// 仅在写入轮数和总时限均未耗尽时允许下一轮写入。
    public static func shouldWrite(afterAttempt attempt: Int, elapsed: TimeInterval) -> Bool {
        attempt < maximumWriteAttempts && elapsed < verificationTimeout
    }

    /// 根据已经完成的写入轮次返回下一次回读前的退避间隔。
    public static func verificationDelay(afterAttempt attempt: Int) -> TimeInterval {
        verificationDelays[min(max(0, attempt), verificationDelays.count - 1)]
    }

    private static func isValid(frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width >= 0
            && frame.height >= 0
    }
}
