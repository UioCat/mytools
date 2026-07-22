import CoreGraphics
import Foundation

public struct WindowLayoutPreviewSegment: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum WindowLayoutMode: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case leftHalf
    case rightHalf
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

public struct WindowLayoutButton: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var modes: [WindowLayoutMode]

    public init(id: String, title: String, modes: [WindowLayoutMode]) {
        self.id = id
        self.title = title
        self.modes = Self.uniqueModes(modes)
    }

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

    static func uniqueModes(_ modes: [WindowLayoutMode]) -> [WindowLayoutMode] {
        var seen = Set<WindowLayoutMode>()
        return modes.filter { seen.insert($0).inserted }
    }
}

public struct WindowLayoutModeShortcuts: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var mode: WindowLayoutMode
    public var shortcuts: [HotKeyBinding]

    public var id: WindowLayoutMode { mode }

    public init(mode: WindowLayoutMode, shortcuts: [HotKeyBinding]) {
        self.mode = mode
        self.shortcuts = Self.uniqueShortcuts(shortcuts)
    }

    static func uniqueShortcuts(_ shortcuts: [HotKeyBinding]) -> [HotKeyBinding] {
        var seen = Set<HotKeyBinding>()
        return shortcuts.filter { shortcut in
            shortcut.isUsableGlobalShortcut && seen.insert(shortcut).inserted
        }
    }
}

struct WindowLayoutModeGroup: Equatable, Identifiable, Sendable {
    var title: String
    var modes: [WindowLayoutMode]

    var id: String { title }
}

enum WindowLayoutSettingsLayout {
    static let modeGroups: [WindowLayoutModeGroup] = [
        WindowLayoutModeGroup(title: "半屏", modes: [.leftHalf, .rightHalf]),
        WindowLayoutModeGroup(title: "三分之一", modes: [.leftThird, .rightThird]),
        WindowLayoutModeGroup(title: "三分之二", modes: [.leftTwoThirds, .rightTwoThirds]),
        WindowLayoutModeGroup(title: "焦点", modes: [.centered, .maximize])
    ]
}

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

    public func shortcuts(for mode: WindowLayoutMode) -> [HotKeyBinding] {
        modeShortcuts.first { $0.mode == mode }?.shortcuts ?? []
    }

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

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case enabledModes
        case customButtons
        case modeShortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            enabledModes: try container.decodeIfPresent([WindowLayoutMode].self, forKey: .enabledModes)
                ?? WindowLayoutMode.allCases,
            customButtons: try container.decodeIfPresent([WindowLayoutButton].self, forKey: .customButtons) ?? [],
            modeShortcuts: try container.decodeIfPresent([WindowLayoutModeShortcuts].self, forKey: .modeShortcuts) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(enabledModes, forKey: .enabledModes)
        try container.encode(customButtons, forKey: .customButtons)
        try container.encode(modeShortcuts, forKey: .modeShortcuts)
    }

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
}

public enum WindowLayoutCalculator {
    public static let centeredScale: CGFloat = 0.8

    public static func targetFrame(for mode: WindowLayoutMode, in visibleFrame: CGRect) -> CGRect {
        switch mode {
        case .leftHalf:
            return leadingFrame(widthFraction: 0.5, in: visibleFrame)
        case .rightHalf:
            return trailingFrame(widthFraction: 0.5, in: visibleFrame)
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

    private static func leadingFrame(widthFraction: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var frame = visibleFrame
        frame.size.width = floor(visibleFrame.width * widthFraction)
        return frame
    }

    private static func trailingFrame(widthFraction: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var frame = leadingFrame(widthFraction: widthFraction, in: visibleFrame)
        frame.origin.x = visibleFrame.maxX - frame.width
        return frame
    }

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
