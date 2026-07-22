import AppKit
import SwiftUI

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
        if credentialUnavailable { return "Keychain 凭据不可访问" }
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
struct TranslationAPIKeyInputMode {
    let isRevealed: Bool

    var usesSecureField: Bool {
        !isRevealed
    }
}

enum TranslationAPIKeyKeyboardCommand: Equatable {
    case copy
    case paste

    static func command(forKeyCode keyCode: UInt16, isCommandPressed: Bool) -> TranslationAPIKeyKeyboardCommand? {
        command(
            forKeyCode: keyCode,
            charactersIgnoringModifiers: nil,
            isCommandPressed: isCommandPressed
        )
    }

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

    static func copyableString(from apiKey: String) -> String? {
        normalizedAPIKey(from: apiKey)
    }

    static func pastedAPIKey(from pasteboardString: String?) -> String? {
        guard let pasteboardString else {
            return nil
        }

        return normalizedAPIKey(from: pasteboardString)
    }

    private static func normalizedAPIKey(from value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

struct TranslationAPIKeyEditableField: NSViewRepresentable {
    @Binding var text: String
    let isSecure: Bool
    let placeholder: String
    let onCopy: (Bool) -> Void
    let onPaste: (Bool) -> Void

    func makeNSView(context: Context) -> TranslationAPIKeyNativeInputView {
        let view = TranslationAPIKeyNativeInputView()
        updateNSView(view, context: context)
        return view
    }

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        isEditing = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        isEditing = false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }

        onTextChange(field.stringValue)
    }

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

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

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

@MainActor
protocol TranslationAPIKeyCommandHandlingField: AnyObject {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)? { get set }
}

final class TranslationAPIKeyTextField: NSTextField, TranslationAPIKeyCommandHandlingField {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommandKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onCommandKeyEquivalent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}

final class TranslationAPIKeySecureTextField: NSSecureTextField, TranslationAPIKeyCommandHandlingField {
    var onCommandKeyEquivalent: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onCommandKeyEquivalent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onCommandKeyEquivalent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }
}
