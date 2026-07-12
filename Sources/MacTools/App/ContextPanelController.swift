import AppKit
import MacToolsCore
import SwiftUI

private enum ContextPanelActionResult {
    case close
    case keepVisible
}

final class ContextPanelController {
    private let fileActionService: FileActionService
    private let pasteboard: WritablePasteboard
    private let windowLayoutService: SystemWindowLayoutService
    private let windowLayoutButtons: () -> [WindowLayoutButton]
    private let logger: Logger
    private var panel: NSPanel?
    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?

    init(
        fileActionService: FileActionService,
        pasteboard: WritablePasteboard,
        windowLayoutService: SystemWindowLayoutService,
        windowLayoutButtons: @escaping () -> [WindowLayoutButton],
        logger: Logger
    ) {
        self.fileActionService = fileActionService
        self.pasteboard = pasteboard
        self.windowLayoutService = windowLayoutService
        self.windowLayoutButtons = windowLayoutButtons
        self.logger = logger
    }

    deinit {
        stopOutsideClickDismissMonitors()
    }

    func show(item: ClipboardItem) {
        let layoutButtons = windowLayoutButtons()
        let content = SuperPanelContent.fileSystem(item: item, windowLayoutButtons: layoutButtons)
        show(content: content) { [weak self] actionID in
            self?.performFileAction(actionID, item: item, windowLayoutButtons: layoutButtons) ?? .close
        }
    }

    func showWindowLayoutOnly() {
        let layoutButtons = windowLayoutButtons()
        let content = SuperPanelContent.windowLayoutOnly(
            windowLayoutButtons: layoutButtons
        )
        show(content: content) { [weak self] actionID in
            guard case .windowLayoutButton(let id) = actionID else {
                self?.logger.error("unexpected window-layout-only action: \(actionID.rawValue)")
                return .close
            }
            return self?.performWindowLayoutAction(id, buttons: layoutButtons) ?? .close
        }
    }

    func showText(
        originalText: String,
        translation: Result<TranslationResponse, TranslationError>?,
        isTranslationLoading: Bool = false,
        reposition: Bool = true
    ) {
        let content = SuperPanelContent.text(
            originalText: originalText,
            translation: translation,
            isTranslationLoading: isTranslationLoading
        )
        let translatedText: String?
        if case .success(let response) = translation {
            translatedText = response.translatedText
        } else {
            translatedText = nil
        }

        show(content: content, reposition: reposition) { [weak self] actionID in
            self?.performTextAction(
                actionID,
                originalText: originalText,
                translatedText: translatedText
            ) ?? .close
        }
    }

    private func show(
        content: SuperPanelContent,
        reposition: Bool = true,
        performAction: @escaping (SuperPanelActionID) -> ContextPanelActionResult
    ) {
        let view = ContextActionView(
            content: content,
            performAction: { [weak self] actionID in
                let result = performAction(actionID)
                if result == .close {
                    self?.hide()
                }
            }
        )

        if panel == nil {
            panel = makePanel()
        }

        let contentSize = panelSize(for: content)
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        panel?.contentView = hostingView
        ContextPanelWindowAppearance.configureRoundedBackingLayer(hostingView)
        if let frameView = hostingView.superview {
            ContextPanelWindowAppearance.configureRoundedBackingLayer(frameView)
        }
        panel?.setContentSize(contentSize)
        if reposition {
            panel?.setFrameOrigin(panelOrigin(for: panel?.frame.size ?? contentSize))
        }
        panel?.orderFrontRegardless()
        startOutsideClickDismissMonitors()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 210),
            styleMask: ContextPanelWindowAppearance.windowStyleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = ContextPanelWindowAppearance.usesSystemWindowShadow
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        return panel
    }

    private func panelSize(for content: SuperPanelContent) -> NSSize {
        SuperPanelLayout.panelSize(for: content)
    }

    private func panelOrigin(for size: NSSize) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        guard let screenFrame = NSScreen.screens
            .first(where: { $0.frame.contains(mouseLocation) })?
            .visibleFrame ?? NSScreen.main?.visibleFrame else {
            return NSPoint(x: mouseLocation.x, y: mouseLocation.y - size.height)
        }

        let padding: CGFloat = 16
        var x = mouseLocation.x + 10
        var y = mouseLocation.y - size.height - 10

        if x + size.width > screenFrame.maxX - padding {
            x = mouseLocation.x - size.width - 10
        }
        if x < screenFrame.minX + padding {
            x = screenFrame.minX + padding
        }
        if y < screenFrame.minY + padding {
            y = min(mouseLocation.y + 10, screenFrame.maxY - size.height - padding)
        }
        if y + size.height > screenFrame.maxY - padding {
            y = screenFrame.maxY - size.height - padding
        }

        return NSPoint(x: x, y: y)
    }

    private func hide() {
        panel?.orderOut(nil)
        stopOutsideClickDismissMonitors()
    }

    private func showTextTransit(_ text: String) {
        let content = SuperPanelContent.textTransit(text: text)
        show(content: content, reposition: false) { [weak self] actionID in
            self?.performTextAction(
                actionID,
                originalText: text,
                translatedText: nil
            ) ?? .close
        }
    }

    private func startOutsideClickDismissMonitors() {
        if localDismissMonitor == nil {
            localDismissMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.hideIfClickIsOutsidePanel(eventScreenLocation: Self.screenLocation(for: event))
                return event
            }
        }

        if globalDismissMonitor == nil {
            globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                self?.hideIfClickIsOutsidePanel(eventScreenLocation: NSEvent.mouseLocation)
            }
        }
    }

    private func stopOutsideClickDismissMonitors() {
        if let localDismissMonitor {
            NSEvent.removeMonitor(localDismissMonitor)
            self.localDismissMonitor = nil
        }

        if let globalDismissMonitor {
            NSEvent.removeMonitor(globalDismissMonitor)
            self.globalDismissMonitor = nil
        }
    }

    private func hideIfClickIsOutsidePanel(eventScreenLocation: NSPoint) {
        guard let panel, panel.isVisible else {
            return
        }

        if PanelOutsideClickPolicy.shouldDismiss(
            panelFrame: panel.frame,
            eventScreenLocation: eventScreenLocation
        ) {
            hide()
        }
    }

    private static func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func performTextAction(
        _ actionID: SuperPanelActionID,
        originalText: String,
        translatedText: String?
    ) -> ContextPanelActionResult {
        switch actionID {
        case .copyTranslatedText:
            guard let translatedText else {
                logger.error("copy translated text failed: no translated text")
                return .close
            }
            pasteboard.writeText(translatedText)
            logger.info("super panel copied translated text")
            return .close
        case .textTransit:
            showTextTransit(originalText)
            return .keepVisible
        case .copyTransitText:
            pasteboard.writeText(Self.normalizedText(originalText))
            logger.info("super panel copied transit text")
            return .close
        case .copyPath, .createNewFile, .openTerminal, .revealInFinder, .openClaudeCode,
             .openClaudeCodeSkipConfirmation, .windowLayoutButton:
            logger.error("unexpected text action: \(actionID.rawValue)")
            return .close
        }
    }

    private func performFileAction(
        _ actionID: SuperPanelActionID,
        item: ClipboardItem,
        windowLayoutButtons: [WindowLayoutButton]
    ) -> ContextPanelActionResult {
        switch actionID {
        case .copyPath:
            copyPath(item)
        case .createNewFile:
            createNewFile(item)
        case .openTerminal:
            openTerminal(item)
        case .revealInFinder:
            reveal(item)
        case .openClaudeCode, .openClaudeCodeSkipConfirmation:
            openClaudeCode(item, skipConfirmation: actionID == .openClaudeCodeSkipConfirmation)
        case .windowLayoutButton(let id):
            return performWindowLayoutAction(id, buttons: windowLayoutButtons)
        case .copyTranslatedText, .textTransit, .copyTransitText:
            logger.error("unexpected file action: \(actionID.rawValue)")
        }

        return .close
    }

    private func performWindowLayoutAction(
        _ id: String,
        buttons: [WindowLayoutButton]
    ) -> ContextPanelActionResult {
        guard let button = buttons.first(where: { $0.id == id }) else {
            logger.error("window layout button missing: \(id)")
            return .close
        }

        do {
            try windowLayoutService.apply(button: button)
        } catch {
            logger.error("window layout failed: \(error)")
        }

        return .close
    }

    private func copyPath(_ item: ClipboardItem) {
        do {
            try fileActionService.copyPath(item: item, pasteboard: pasteboard)
        } catch {
            logger.error("copy path failed: \(error)")
        }
    }

    private func openTerminal(_ item: ClipboardItem) {
        do {
            guard let path = item.originalPath else {
                throw FileActionError.missingPath
            }
            try fileActionService.openTerminal(at: path)
        } catch {
            logger.error("open terminal failed: \(error)")
        }
    }

    private func createNewFile(_ item: ClipboardItem) {
        do {
            let fileURL = try fileActionService.createNewFile(in: item)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            logger.info("created file from super panel: \(fileURL.path)")
        } catch {
            logger.error("create file failed: \(error)")
        }
    }

    private func openClaudeCode(_ item: ClipboardItem, skipConfirmation: Bool) {
        do {
            guard let path = item.originalPath else {
                throw FileActionError.missingPath
            }
            try fileActionService.openExternalApplication(named: "Claude", at: path)
            logger.info("opened Claude from super panel; skipConfirmation=\(skipConfirmation)")
        } catch {
            logger.error("open Claude Code failed: \(error)")
        }
    }

    private func reveal(_ item: ClipboardItem) {
        do {
            try fileActionService.revealInFinder(item)
        } catch {
            logger.error("reveal in finder failed: \(error)")
        }
    }

    private static func normalizedText(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? text : trimmedText
    }
}
