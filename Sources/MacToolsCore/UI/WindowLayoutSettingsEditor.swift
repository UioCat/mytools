// `WindowLayoutSettingsEditor` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import AppKit
import SwiftUI

/// 封装 `WindowLayoutSettingsEditor` 在 SwiftUI 展示层中的值语义和相关操作。
struct WindowLayoutSettingsEditor: View {
    let currentSettings: WindowLayoutSettings
    let reservedShortcuts: [HotKeyBinding]
    @Binding var isEnabled: Bool
    @Binding var enabledModes: Set<WindowLayoutMode>
    @Binding var modeShortcuts: [WindowLayoutModeShortcuts]
    @Binding var saveMessage: String?
    let saveWindowLayoutSettings: (WindowLayoutSettings) throws -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("状态")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)

                Spacer()

                Text(saveMessage ?? "已保存")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MacToolsGlassTheme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 50, alignment: .trailing)
                    .opacity(saveMessage == nil ? 0 : 1)

                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Divider()
                .overlay(MacToolsGlassTheme.divider)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    sectionHeader("面板动作")
                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 4)

                ForEach(Array(WindowLayoutSettingsLayout.modeGroups.enumerated()), id: \.element.id) { index, group in
                    modeGroupRow(group)

                    if index != WindowLayoutSettingsLayout.modeGroups.count - 1 {
                        Divider()
                            .overlay(MacToolsGlassTheme.divider)
                            .opacity(0.7)
                            .padding(.leading, 86)
                    }
                }
            }
            .disabled(!isEnabled)
        }
        .onChange(of: currentSettings) { _, settings in
            isEnabled = settings.isEnabled
            enabledModes = Set(settings.enabledModes)
            modeShortcuts = settings.modeShortcuts
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                isEnabled = newValue
                save()
            }
        )
    }

    /// 构建并返回 `modeGroupRow` 对应的 SwiftUI 界面内容或展示状态。
    private func modeGroupRow(_ group: WindowLayoutModeGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(group.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacToolsGlassTheme.textTertiary)
                .frame(width: 62, alignment: .leading)
                .padding(.top, 14)

            HStack(alignment: .top, spacing: 8) {
                ForEach(group.modes) { mode in
                    WindowLayoutModeActionCell(
                        mode: mode,
                        isPresentedInPanel: enabledModes.contains(mode),
                        isSettingsEnabled: isEnabled,
                        shortcut: shortcuts(for: mode).first,
                        togglePanelVisibility: { shouldShow in
                            setMode(mode, isEnabled: shouldShow)
                        },
                        updateShortcut: { shortcut in
                            replaceShortcut(for: mode, with: shortcut)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// 更新布局模式是否出现在操作面板，并立即保存设置。
    private func setMode(_ mode: WindowLayoutMode, isEnabled: Bool) {
        if isEnabled {
            enabledModes.insert(mode)
        } else {
            enabledModes.remove(mode)
        }
        save()
    }

    /// 构建并返回 `sectionHeader` 对应的 SwiftUI 界面内容或展示状态。
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MacToolsGlassTheme.textTertiary)
    }

    /// 构建并返回 `shortcuts` 对应的 SwiftUI 界面内容或展示状态。
    private func shortcuts(for mode: WindowLayoutMode) -> [HotKeyBinding] {
        modeShortcuts.first { $0.mode == mode }?.shortcuts ?? []
    }

    /// 校验全局快捷键可用性和冲突后，替换指定布局模式的主快捷键。
    @discardableResult
    private func replaceShortcut(for mode: WindowLayoutMode, with shortcut: HotKeyBinding?) -> Bool {
        guard let shortcut else {
            modeShortcuts = draftSettings.replacingPrimaryShortcut(for: mode, with: nil).modeShortcuts
            save()
            return true
        }

        guard shortcut.isUsableGlobalShortcut else {
            saveMessage = "请先输入快捷键"
            return false
        }

        let shortcutsInOtherModes = Set(
            modeShortcuts
                .filter { $0.mode != mode }
                .flatMap(\.shortcuts)
        )
        guard !reservedShortcuts.contains(shortcut), !shortcutsInOtherModes.contains(shortcut) else {
            saveMessage = "快捷键已存在"
            return false
        }

        modeShortcuts = draftSettings.replacingPrimaryShortcut(for: mode, with: shortcut).modeShortcuts
        save()
        return true
    }

    /// 保存 `save` 接收的 SwiftUI 展示层数据，并保持既有持久化约束。
    private func save() {
        let updatedSettings = draftSettings
        modeShortcuts = updatedSettings.modeShortcuts

        do {
            try saveWindowLayoutSettings(updatedSettings)
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }

    private var draftSettings: WindowLayoutSettings {
        WindowLayoutSettings(
            isEnabled: isEnabled,
            enabledModes: WindowLayoutMode.allCases.filter { enabledModes.contains($0) },
            modeShortcuts: modeShortcuts
        )
    }
}
/// 封装 `WindowLayoutModeActionCell` 在 SwiftUI 展示层中的值语义和相关操作。
struct WindowLayoutModeActionCell: View {
    let mode: WindowLayoutMode
    let isPresentedInPanel: Bool
    let isSettingsEnabled: Bool
    let shortcut: HotKeyBinding?
    let togglePanelVisibility: (Bool) -> Void
    let updateShortcut: (HotKeyBinding?) -> Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                WindowLayoutModePreviewIcon(mode: mode)
                    .frame(width: 36, height: 24)

                Text(mode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MacToolsGlassTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { isPresentedInPanel },
                        set: { isEnabled in
                            togglePanelVisibility(isEnabled)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!isSettingsEnabled)
                .help(isPresentedInPanel ? "从面板隐藏" : "在面板显示")
            }

            shortcutEditor
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .opacity(isSettingsEnabled ? (isPresentedInPanel ? 1 : 0.62) : 0.45)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? MacToolsGlassTheme.activeBlue.opacity(0.12) : Color.white.opacity(0.050))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isHovered ? MacToolsGlassTheme.activeBlue.opacity(0.34) : MacToolsGlassTheme.border, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var shortcutEditor: some View {
        HStack(spacing: 8) {
            WindowLayoutShortcutCaptureField(
                shortcut: shortcut,
                placeholder: "按下快捷键",
                onShortcutChange: updateShortcut
            )
            .frame(height: 32)
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MacToolsGlassTheme.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(MacToolsGlassTheme.border, lineWidth: 1)
            )

            Button {
                _ = updateShortcut(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(
                        width: MacToolsControlMetrics.inlineIconSize.width,
                        height: MacToolsControlMetrics.inlineIconSize.height
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(shortcut == nil ? MacToolsGlassTheme.textDisabled : MacToolsGlassTheme.textTertiary)
            .disabled(shortcut == nil || !isSettingsEnabled)
            .help("删除快捷键")
            .accessibilityLabel(Text("删除快捷键"))
        }
    }
}

/// 封装 `WindowLayoutShortcutCaptureField` 在 SwiftUI 展示层中的值语义和相关操作。
struct WindowLayoutShortcutCaptureField: NSViewRepresentable {
    let shortcut: HotKeyBinding?
    let placeholder: String
    let onShortcutChange: (HotKeyBinding?) -> Bool

    /// 构造并返回 `makeNSView` 所描述的 SwiftUI 展示层对象。
    func makeNSView(context: Context) -> WindowLayoutShortcutCaptureTextField {
        let field = WindowLayoutShortcutCaptureTextField()
        updateNSView(field, context: context)
        return field
    }

    /// 更新快捷键捕获视图回调，并在请求令牌变化时重新获取焦点。
    func updateNSView(_ nsView: WindowLayoutShortcutCaptureTextField, context: Context) {
        nsView.configure(
            shortcut: shortcut,
            placeholder: placeholder,
            onShortcutChange: onShortcutChange
        )
    }
}

/// 管理 `WindowLayoutShortcutCaptureTextField` 在 SwiftUI 展示层中的生命周期、依赖和可变状态。
final class WindowLayoutShortcutCaptureTextField: NSTextField {
    private var currentShortcut: HotKeyBinding?
    private var onShortcutChange: (HotKeyBinding?) -> Bool = { _ in true }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 150, height: 30)
    }

    /// 创建 `WindowLayoutShortcutCaptureTextField`，保存传入依赖并建立初始状态。
    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        focusRingType = .none
        cell = VerticallyCenteredTextFieldCell()
        alignment = .center
        lineBreakMode = .byTruncatingTail
        font = .systemFont(ofSize: 12, weight: .medium)
        textColor = NSColor.white.withAlphaComponent(0.78)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    /// 创建 `WindowLayoutShortcutCaptureTextField`，保存传入依赖并建立初始状态。
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 更新快捷键捕获框的当前值、占位文本和变更回调。
    func configure(
        shortcut: HotKeyBinding?,
        placeholder: String,
        onShortcutChange: @escaping (HotKeyBinding?) -> Bool
    ) {
        currentShortcut = shortcut
        self.onShortcutChange = onShortcutChange
        placeholderString = placeholder
        let displayValue = shortcut?.displayValue ?? ""
        if stringValue != displayValue {
            stringValue = displayValue
        }
    }

    /// 响应 `mouseDown` 对应的系统或界面回调，并同步当前交互状态。
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
    override func keyDown(with event: NSEvent) {
        _ = capture(event)
    }

    /// 拦截快捷键组合并交给捕获回调；无有效修饰键时保留系统处理。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        return capture(event)
    }

    /// 构建并返回 `capture` 对应的 SwiftUI 界面内容或展示状态。
    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, Self.modifierNames(from: event).isEmpty {
            if onShortcutChange(nil) {
                currentShortcut = nil
                stringValue = ""
            }
            return true
        }

        guard let shortcut = Self.shortcut(from: event) else {
            NSSound.beep()
            return true
        }

        if onShortcutChange(shortcut) {
            currentShortcut = shortcut
            stringValue = shortcut.displayValue
        } else {
            stringValue = currentShortcut?.displayValue ?? ""
        }
        return true
    }

    /// 构建并返回 `shortcut` 对应的 SwiftUI 界面内容或展示状态。
    private static func shortcut(from event: NSEvent) -> HotKeyBinding? {
        let modifiers = modifierNames(from: event)
        guard !modifiers.isEmpty, let key = keyName(from: event) else {
            return nil
        }
        return HotKeyBinding(key: key, modifiers: modifiers)
    }

    /// 构建并返回 `modifierNames` 对应的 SwiftUI 界面内容或展示状态。
    private static func modifierNames(from event: NSEvent) -> [String] {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: [String] = []
        if flags.contains(.control) {
            modifiers.append("Control")
        }
        if flags.contains(.option) {
            modifiers.append("Option")
        }
        if flags.contains(.shift) {
            modifiers.append("Shift")
        }
        if flags.contains(.command) {
            modifiers.append("Command")
        }
        return modifiers
    }

    /// 构建并返回 `keyName` 对应的 SwiftUI 界面内容或展示状态。
    private static func keyName(from event: NSEvent) -> String? {
        if let keyName = keyNamesByCode[event.keyCode] {
            return keyName
        }

        guard let character = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
              !character.isEmpty
        else {
            return nil
        }

        if character == " " {
            return "Space"
        }

        return character.count == 1 ? character.uppercased() : nil
    }

    private static let keyNamesByCode: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        109: "F10",
        111: "F12",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]
}

/// 管理 `VerticallyCenteredTextFieldCell` 在 SwiftUI 展示层中的生命周期、依赖和可变状态。
final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    /// 构建并返回 `drawingRect` 对应的 SwiftUI 界面内容或展示状态。
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(super.drawingRect(forBounds: rect), in: rect)
    }

    /// 构建并返回 `titleRect` 对应的 SwiftUI 界面内容或展示状态。
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredRect(super.titleRect(forBounds: rect), in: rect)
    }

    /// 构建并返回 `centeredRect` 对应的 SwiftUI 界面内容或展示状态。
    private func centeredRect(_ textRect: NSRect, in bounds: NSRect) -> NSRect {
        var rect = textRect
        rect.size.height = min(bounds.height, ceil(cellSize(forBounds: bounds).height))
        rect.origin.y = bounds.origin.y + (bounds.height - rect.height) / 2
        return rect
    }
}

/// 封装 `WindowLayoutModePreviewIcon` 在 SwiftUI 展示层中的值语义和相关操作。
struct WindowLayoutModePreviewIcon: View {
    let mode: WindowLayoutMode

    var body: some View {
        WindowLayoutPreviewIcon(segments: [mode.previewSegment])
    }
}

/// 封装 `WindowLayoutPreviewIcon` 在 SwiftUI 展示层中的值语义和相关操作。
struct WindowLayoutPreviewIcon: View {
    let segments: [WindowLayoutPreviewSegment]

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let screen = WindowLayoutPreviewGeometry.screenFrame(in: bounds)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: screen.minX, y: screen.minY)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.34), lineWidth: 1)
                    .frame(width: screen.width, height: screen.height)
                    .offset(x: screen.minX, y: screen.minY)

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    let target = WindowLayoutPreviewGeometry.targetFrame(for: segment, in: bounds)

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(MacToolsGlassTheme.activeBlue.opacity(index == 0 ? 0.82 : 0.58))
                        .overlay(
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .strokeBorder(MacToolsGlassTheme.activeBlue.opacity(0.88), lineWidth: 0.8)
                        )
                        .frame(
                            width: target.width,
                            height: target.height
                        )
                        .offset(
                            x: target.minX,
                            y: target.minY
                        )
                }
            }
        }
        .aspectRatio(1.42, contentMode: .fit)
    }
}
