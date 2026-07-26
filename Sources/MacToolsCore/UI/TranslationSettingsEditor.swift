// `TranslationSettingsEditor` 的 SwiftUI 展示层实现。
// 负责视图状态、布局和用户操作回调，不直接拥有系统集成生命周期。

import AppKit
import SwiftUI

/// 封装 `TranslationSettingsEditor` 在 SwiftUI 展示层中的值语义和相关操作。
struct TranslationSettingsEditor: View {
    let currentSettings: TranslationSettings
    let credentialUnavailable: Bool
    @Binding var apiKey: String
    @Binding var model: String
    @Binding var endpointURLString: String
    @Binding var isAPIKeyRevealed: Bool
    @Binding var saveMessage: String?
    let saveTranslationSettings: (TranslationSettings) async throws -> Void
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "服务", value: "阿里云百炼")
            SettingsRow(title: "状态", value: credentialStatusText)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("API Key")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MacToolsGlassTheme.textPrimary)

                    Spacer(minLength: 12)

                    apiKeyControl
                        .frame(maxWidth: 240, alignment: .trailing)
                }

                Divider()
                    .overlay(MacToolsGlassTheme.divider)
                    .opacity(0.9)

                labeledTextField(title: "模型", text: $model)

                Divider()
                    .overlay(MacToolsGlassTheme.divider)
                    .opacity(0.9)

                labeledTextField(title: "Endpoint", text: $endpointURLString)

                HStack(spacing: 10) {
                    Button(action: save) {
                        Label("保存", systemImage: "tray.and.arrow.down")
                            .font(.system(size: MacToolsControlMetrics.textActionFontSize, weight: .semibold))
                    }
                    .buttonStyle(GlassPrimaryButtonStyle(cornerRadius: 14))
                    .disabled(isSaving)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MacToolsGlassTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var credentialStatusText: String {
        if credentialUnavailable { return "翻译凭据暂时不可用" }
        return currentSettings.isConfigured ? "已安全保存" : "未配置"
    }

    @ViewBuilder
    private var apiKeyControl: some View {
        HStack(spacing: 8) {
            TranslationAPIKeyEditableField(
                text: $apiKey,
                isSecure: TranslationAPIKeyInputMode(isRevealed: isAPIKeyRevealed).usesSecureField,
                placeholder: "DASHSCOPE_API_KEY",
                onCopy: { didCopy in
                    saveMessage = didCopy ? "已复制 API Key" : "没有可复制的 API Key"
                },
                onPaste: { didPaste in
                    if didPaste {
                        isAPIKeyRevealed = true
                        saveMessage = "已粘贴 API Key"
                    } else {
                        saveMessage = "剪贴板没有 API Key"
                    }
                }
            )
            .frame(height: 22)
            .frame(minWidth: 92, maxWidth: .infinity, alignment: .trailing)
            .layoutPriority(1)

            apiKeyIconButton(
                systemName: isAPIKeyRevealed ? "eye.slash" : "eye",
                help: isAPIKeyRevealed ? "隐藏 API Key" : "显示 API Key"
            ) {
                isAPIKeyRevealed.toggle()
            }
        }
    }

    /// 构建并返回 `labeledTextField` 对应的 SwiftUI 界面内容或展示状态。
    private func labeledTextField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacToolsGlassTheme.textPrimary)

            Spacer(minLength: 12)

            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(maxWidth: 190)
        }
    }

    /// 构建并返回 `apiKeyIconButton` 对应的 SwiftUI 界面内容或展示状态。
    private func apiKeyIconButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(
                    width: MacToolsControlMetrics.inlineIconSize.width,
                    height: MacToolsControlMetrics.inlineIconSize.height
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(MacToolsGlassTheme.textSecondary)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    /// 组装翻译设置草稿并异步保存，保存期间阻止重复提交。
    private func save() {
        let trimmedEndpoint = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard URL(string: trimmedEndpoint) != nil else {
            saveMessage = "Endpoint URL 无效"
            return
        }

        var updatedSettings = currentSettings
        updatedSettings.providerID = TranslationSettings.defaultProviderID
        updatedSettings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSettings.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedSettings.endpointURLString = trimmedEndpoint

        isSaving = true
        saveMessage = "正在保存…"
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await saveTranslationSettings(updatedSettings)
                saveMessage = "已保存"
                if updatedSettings.isConfigured {
                    isAPIKeyRevealed = false
                }
            } catch {
                saveMessage = "保存失败"
            }
        }
    }
}
/// 封装 `TranslationAPIKeyInputMode` 在 SwiftUI 展示层中的值语义和相关操作。
struct TranslationAPIKeyInputMode {
    let isRevealed: Bool

    var usesSecureField: Bool {
        !isRevealed
    }
}

/// 描述 `TranslationAPIKeyKeyboardCommand` 在 SwiftUI 展示层中可取的状态、选项或错误。
enum TranslationAPIKeyKeyboardCommand: Equatable {
    case copy
    case paste

    /// 构建并返回 `command` 对应的 SwiftUI 界面内容或展示状态。
    static func command(forKeyCode keyCode: UInt16, isCommandPressed: Bool) -> TranslationAPIKeyKeyboardCommand? {
        command(
            forKeyCode: keyCode,
            charactersIgnoringModifiers: nil,
            isCommandPressed: isCommandPressed
        )
    }

    /// 构建并返回 `command` 对应的 SwiftUI 界面内容或展示状态。
    static func command(
        forKeyCode keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        isCommandPressed: Bool
    ) -> TranslationAPIKeyKeyboardCommand? {
        guard isCommandPressed else {
            return nil
        }

        switch charactersIgnoringModifiers?.lowercased() {
        case "c":
            return .copy
        case "v":
            return .paste
        default:
            break
        }

        switch keyCode {
        case 8:
            return .copy
        case 9:
            return .paste
        default:
            return nil
        }
    }

    /// 执行 `copyableString` 对应的 SwiftUI 展示层输入输出操作。
    static func copyableString(from apiKey: String) -> String? {
        normalizedAPIKey(from: apiKey)
    }

    /// 执行 `pastedAPIKey` 对应的 SwiftUI 展示层输入输出操作。
    static func pastedAPIKey(from pasteboardString: String?) -> String? {
        guard let pasteboardString else {
            return nil
        }

        return normalizedAPIKey(from: pasteboardString)
    }

    /// 转换 `normalizedAPIKey` 接收的 SwiftUI 展示层数据，并返回规范化结果。
    private static func normalizedAPIKey(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

/// 封装 `TranslationAPIKeyEditableField` 在 SwiftUI 展示层中的值语义和相关操作。
struct TranslationAPIKeyEditableField: NSViewRepresentable {
    @Binding var text: String
    let isSecure: Bool
    let placeholder: String
    let onCopy: (Bool) -> Void
    let onPaste: (Bool) -> Void

    /// 构造并返回 `makeNSView` 所描述的 SwiftUI 展示层对象。
    func makeNSView(context: Context) -> TranslationAPIKeyNativeInputView {
        let view = TranslationAPIKeyNativeInputView()
        updateNSView(view, context: context)
        return view
    }

    /// 同步文本和 IME 组合状态，但不在编辑器已有未提交输入时抢占焦点。
    func updateNSView(_ nsView: TranslationAPIKeyNativeInputView, context: Context) {
        nsView.configure(
            text: text,
            isSecure: isSecure,
            placeholder: placeholder,
            onTextChange: { text = $0 },
            onCopy: onCopy,
            onPaste: onPaste
        )
    }
}

/// 管理 `TranslationAPIKeyNativeInputView` 在 SwiftUI 展示层中的生命周期、依赖和可变状态。
final class TranslationAPIKeyNativeInputView: NSView, NSTextFieldDelegate {
    private var field: NSTextField?
    private var monitor: Any?
    private var isConfiguredAsSecure = false
    private var isEditing = false
    private var onTextChange: (String) -> Void = { _ in }
    private var onCopy: (Bool) -> Void = { _ in }
    private var onPaste: (Bool) -> Void = { _ in }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 140, height: 22)
    }

    /// 更新 API Key 输入框配置；明文与安全输入模式变化时重建原生文本框。
    func configure(
        text: String,
        isSecure: Bool,
        placeholder: String,
        onTextChange: @escaping (String) -> Void,
        onCopy: @escaping (Bool) -> Void,
        onPaste: @escaping (Bool) -> Void
    ) {
        self.onTextChange = onTextChange
        self.onCopy = onCopy
        self.onPaste = onPaste

        if field == nil || isConfiguredAsSecure != isSecure {
            replaceField(isSecure: isSecure)
        }

        field?.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.32)
            ]
        )
        if field?.stringValue != text {
            field?.stringValue = text
        }
    }

    /// 文本视图进入窗口后安装键盘监听。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    /// 文本视图离开窗口前移除键盘监听。
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    /// 标记原生文本框进入编辑状态，使键盘命令只在当前编辑期间生效。
    func controlTextDidBeginEditing(_ notification: Notification) {
        isEditing = true
    }

    /// 标记原生文本框结束编辑。
    func controlTextDidEndEditing(_ notification: Notification) {
        isEditing = false
    }

    /// 将原生文本框的最新内容回传给 SwiftUI 绑定。
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }

        onTextChange(field.stringValue)
    }

    /// 在明文框与安全输入框之间切换，并重新建立布局和事件回调。
    private func replaceField(isSecure: Bool) {
        let previousField = field
        let replacement: NSTextField = isSecure ? TranslationAPIKeySecureTextField() : TranslationAPIKeyTextField()
        configureField(replacement)

        previousField?.removeFromSuperview()
        field = replacement
        isConfiguredAsSecure = isSecure
        isEditing = false

        addSubview(replacement)
        NSLayoutConstraint.activate([
            replacement.leadingAnchor.constraint(equalTo: leadingAnchor),
            replacement.trailingAnchor.constraint(equalTo: trailingAnchor),
            replacement.topAnchor.constraint(equalTo: topAnchor),
            replacement.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        invalidateIntrinsicContentSize()
    }

    /// 统一配置原生文本框外观、代理和命令键处理回调。
    private func configureField(_ field: NSTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = NSColor.white.withAlphaComponent(0.78)
        field.alignment = .right
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.lineBreakMode = .byTruncatingMiddle
        field.delegate = self
        if let commandField = field as? TranslationAPIKeyCommandHandlingField {
            commandField.onCommandKeyEquivalent = { [weak self] event in
                self?.handleKeyDown(event) ?? false
            }
        }
    }

    /// 仅在视图已进入窗口时安装一次本地键盘事件监听。
    private func updateMonitor() {
        if window == nil {
            removeMonitor()
            return
        }

        guard monitor == nil else {
            return
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKeyDown(event) else {
                return event
            }

            return nil
        }
    }

    /// 移除已安装的本地事件监听并清空句柄。
    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// 在 API Key 编辑期间拦截复制、粘贴等命令，并交由注入的处理闭包执行。
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard
            isEditingAPIKeyField(),
            let command = TranslationAPIKeyKeyboardCommand.command(
                forKeyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                isCommandPressed: event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .contains(.command)
            )
        else {
            return false
        }

        switch command {
        case .copy:
            guard let copyableString = TranslationAPIKeyKeyboardCommand.copyableString(from: field?.stringValue ?? "") else {
                onCopy(false)
                return true
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copyableString, forType: .string)
            onCopy(true)
            return true

        case .paste:
            guard let pastedAPIKey = TranslationAPIKeyKeyboardCommand.pastedAPIKey(
                from: NSPasteboard.general.string(forType: .string)
            ) else {
                onPaste(false)
                return true
            }

            field?.stringValue = pastedAPIKey
            onTextChange(pastedAPIKey)
            onPaste(true)
            return true
        }
    }

    /// 判断 `isEditingAPIKeyField` 所描述的 SwiftUI 展示层条件是否成立。
    private func isEditingAPIKeyField() -> Bool {
        if isEditing {
            return true
        }

        guard let field else {
            return false
        }

        if window?.firstResponder === field {
            return true
        }

        guard let editor = field.currentEditor() else {
            return false
        }

        return window?.firstResponder === editor
    }
}

/// 定义 `TranslationAPIKeyCommandHandlingField` 在 SwiftUI 展示层中需要满足的能力边界。
@MainActor
protocol TranslationAPIKeyCommandHandlingField: AnyObject {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)? { get set }
}

/// 管理 `TranslationAPIKeyTextField` 在 SwiftUI 展示层中的生命周期、依赖和可变状态。
final class TranslationAPIKeyTextField: NSTextField, TranslationAPIKeyCommandHandlingField {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)?

    /// 优先处理自定义命令键；未消费的事件继续交给普通文本框。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommandKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
    override func keyDown(with event: NSEvent) {
        if onCommandKeyEquivalent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

/// 管理 `TranslationAPIKeySecureTextField` 在 SwiftUI 展示层中的生命周期、依赖和可变状态。
final class TranslationAPIKeySecureTextField: NSSecureTextField, TranslationAPIKeyCommandHandlingField {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)?

    /// 优先处理自定义命令键；未消费的事件继续交给安全文本框。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommandKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    /// 响应 `keyDown` 对应的系统或界面回调，并同步当前交互状态。
    override func keyDown(with event: NSEvent) {
        if onCommandKeyEquivalent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
