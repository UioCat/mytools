// 超级右键结果面板的 AppKit 展示协调器。
// 负责面板身份、内容更新和动作执行，不负责捕获右键事件或选择内容。

import AppKit
import MacToolsCore
import SwiftUI

/// 描述 `ContextPanelActionResult` 在应用运行时与 AppKit 集成中可取的状态、选项或错误。
private enum ContextPanelActionResult {
    case close
    case keepVisible
}

/// 管理 `ContextPanelController` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class ContextPanelController {
    private let fileActionService: FileActionService
    private let pasteboard: WritablePasteboard
    private let windowLayoutService: SystemWindowLayoutService
    private let windowLayoutButtons: () -> [WindowLayoutButton]
    private let speechController: TranslationSpeechController
    private let logger: Logger
    private var panel: NSPanel?
    private var localDismissMonitor: Any?
    private var globalDismissMonitor: Any?

    /// 创建 `ContextPanelController`，保存传入依赖并建立初始状态。
    init(
        fileActionService: FileActionService,
        pasteboard: WritablePasteboard,
        windowLayoutService: SystemWindowLayoutService,
        windowLayoutButtons: @escaping () -> [WindowLayoutButton],
        speechController: TranslationSpeechController,
        logger: Logger
    ) {
        self.fileActionService = fileActionService
        self.pasteboard = pasteboard
        self.windowLayoutService = windowLayoutService
        self.windowLayoutButtons = windowLayoutButtons
        self.speechController = speechController
        self.logger = logger
    }

    /// 释放当前实例持有的观察者、任务或系统资源。
    deinit {
        MainActor.assumeIsolated {
            stopOutsideClickDismissMonitors()
        }
    }

    /// 展示 `show` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func show(
        item: ClipboardItem,
        presentation: SuperPanelFileSystemPresentation = .selectedItem
    ) {
        let layoutButtons = windowLayoutButtons()
        let content = SuperPanelContent.fileSystem(
            item: item,
            windowLayoutButtons: layoutButtons,
            presentation: presentation
        )
        show(content: content) { [weak self] actionID in
            self?.performFileAction(actionID, item: item, windowLayoutButtons: layoutButtons) ?? .close
        }
    }

    /// 展示 `showWindowLayoutOnly` 对应的应用运行时与 AppKit 集成界面或系统位置。
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

    /// 展示文本操作面板；翻译从加载态更新为结果态时可保持原面板位置。
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

    /// 重建 SwiftUI 内容并复用透明 NSPanel，统一处理尺寸、定位和外部点击关闭。
    private func show(
        content: SuperPanelContent,
        reposition: Bool = true,
        performAction: @escaping (SuperPanelActionID) -> ContextPanelActionResult
    ) {
        reconcileSpeechPlayback(with: content)
        let view = RuntimeContextActionView(
            content: content,
            speechController: speechController,
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
        if let panel {
            ContextPanelWindowAppearance.configurePresentationPolicy(panel)
            panel.orderFrontRegardless()
        }
        startOutsideClickDismissMonitors()
    }

    /// 内容刷新后若已找不到正在朗读的请求，则停止旧语音避免状态悬空。
    private func reconcileSpeechPlayback(with content: SuperPanelContent) {
        guard let activeRequest = speechController.state.activeRequest,
              activeRequest.source == .superRightClick else {
            return
        }

        let keepsActiveRequest = content.previewRows.contains { row in
            row.speechRequest == activeRequest
        }
        if !keepsActiveRequest {
            speechController.stop()
        }
    }

    /// 构造并返回 `makePanel` 所描述的应用运行时与 AppKit 集成对象。
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
        ContextPanelWindowAppearance.configurePresentationPolicy(panel)
        panel.isMovableByWindowBackground = true
        return panel
    }

    /// 计算并返回 `panelSize` 对应的应用运行时与 AppKit 集成数据或状态结果。
    private func panelSize(for content: SuperPanelContent) -> NSSize {
        SuperPanelLayout.panelSize(for: content)
    }

    /// 优先在鼠标右下方放置面板，并将最终位置约束在当前屏幕可见区域内。
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

    /// 取消或关闭 `hide` 对应的应用运行时与 AppKit 集成流程，并清理临时状态。
    private func hide() {
        panel?.orderOut(nil)
        stopOutsideClickDismissMonitors()
    }

    /// 展示 `showTextTransit` 对应的应用运行时与 AppKit 集成界面或系统位置。
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

    /// 同时监听应用内外鼠标按下事件，确保非激活面板也能在外部点击时关闭。
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

    /// 结束 `stopOutsideClickDismissMonitors` 对应的应用运行时与 AppKit 集成流程，并释放或重置相关资源。
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

    /// 取消或关闭 `hideIfClickIsOutsidePanel` 对应的应用运行时与 AppKit 集成流程，并清理临时状态。
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

    /// 计算并返回 `screenLocation` 对应的应用运行时与 AppKit 集成数据或状态结果。
    private static func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    /// 执行 `performTextAction` 指定的应用运行时与 AppKit 集成动作，并返回执行结果。
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
            do {
                try pasteboard.writeText(translatedText)
                logger.info("super panel copied translated text")
                return .close
            } catch {
                logger.error("copy translated text failed: \(error)")
                return .keepVisible
            }
        case .textTransit:
            showTextTransit(originalText)
            return .keepVisible
        case .copyTransitText:
            do {
                try pasteboard.writeText(Self.normalizedText(originalText))
                logger.info("super panel copied transit text")
                return .close
            } catch {
                logger.error("copy transit text failed: \(error)")
                return .keepVisible
            }
        case .copyPath, .createNewFile, .openTerminal, .revealInFinder, .openClaudeCode,
             .openClaudeCodeSkipConfirmation, .windowLayoutButton:
            logger.error("unexpected text action: \(actionID.rawValue)")
            return .close
        }
    }

    /// 执行 `performFileAction` 指定的应用运行时与 AppKit 集成动作，并返回执行结果。
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

    /// 执行 `performWindowLayoutAction` 指定的应用运行时与 AppKit 集成动作，并返回执行结果。
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

    /// 执行 `copyPath` 对应的应用运行时与 AppKit 集成输入输出操作。
    private func copyPath(_ item: ClipboardItem) {
        do {
            try fileActionService.copyPath(item: item, pasteboard: pasteboard)
        } catch {
            logger.error("copy path failed: \(error)")
        }
    }

    /// 展示 `openTerminal` 对应的应用运行时与 AppKit 集成界面或系统位置。
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

    /// 构造并返回 `createNewFile` 所描述的应用运行时与 AppKit 集成对象。
    private func createNewFile(_ item: ClipboardItem) {
        do {
            let fileURL = try fileActionService.createNewFile(in: item)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            logger.info("created file from super panel: \(fileURL.path)")
        } catch {
            logger.error("create file failed: \(error)")
        }
    }

    /// 展示 `openClaudeCode` 对应的应用运行时与 AppKit 集成界面或系统位置。
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

    /// 展示 `reveal` 对应的应用运行时与 AppKit 集成界面或系统位置。
    private func reveal(_ item: ClipboardItem) {
        do {
            try fileActionService.revealInFinder(item)
        } catch {
            logger.error("reveal in finder failed: \(error)")
        }
    }

    /// 转换 `normalizedText` 接收的应用运行时与 AppKit 集成数据，并返回规范化结果。
    private static func normalizedText(_ text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? text : trimmedText
    }
}

/// 封装 `RuntimeContextActionView` 在应用运行时与 AppKit 集成中的值语义和相关操作。
private struct RuntimeContextActionView: View {
    let content: SuperPanelContent
    @ObservedObject var speechController: TranslationSpeechController
    let performAction: (SuperPanelActionID) -> Void

    var body: some View {
        ContextActionView(
            content: content,
            speechState: speechController.state,
            performSpeech: { request in
                speechController.toggle(request)
            },
            performAction: performAction
        )
    }
}
