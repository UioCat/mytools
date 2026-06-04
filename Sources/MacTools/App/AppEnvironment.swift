import AppKit
import Foundation
import MacToolsCore

@MainActor
final class AppEnvironment {
    let logger = Logger()
    private let settingsStore: SettingsStore
    let settings: AppSettings
    private let repository: ClipboardRepository
    private let clipboardService: ClipboardService
    private let pasteActionService: PasteActionService
    private let permissionService = PermissionService()
    private let fileActionService = FileActionService(workspace: SystemWorkspaceOpening())
    private let mainPanelRouter = MainPanelRouter()
    private let mainPanelDismissHandler = PanelDismissHandler()
    private var clipboardTimer: Timer?
    private var appBeforePanel: NSRunningApplication?

    private lazy var clipboardModel = ClipboardPanelModel(
        repository: repository,
        pasteActionService: pasteActionService,
        logger: logger,
        limit: { [settings] in settings.clipboard.maxHistoryCount }
    )

    lazy var mainPanel = MainPanelController(
        initialSize: NSSize(width: 1080, height: 720),
        minimumSize: NSSize(width: 900, height: 620),
        rootView: RuntimeMainWorkspaceView(
            router: mainPanelRouter,
            model: clipboardModel,
            settings: settings,
            permissionService: permissionService,
            onCopy: { [weak self] item in
                self?.copyFromPanel(item)
            },
            onCopyAndPaste: { [weak self] item in
                self?.pasteFromPanel(item)
            },
            onDismiss: { [mainPanelDismissHandler] in
                mainPanelDismissHandler.dismiss()
            }
        )
    )

    private lazy var contextPanel = ContextPanelController(
        fileActionService: fileActionService,
        pasteboard: SystemWritablePasteboard(),
        logger: logger
    )

    private lazy var superRightClickMonitor = SuperRightClickMonitor(
        thresholdMilliseconds: settings.superRightClick.longPressMilliseconds,
        service: SuperRightClickService(
            settings: settings.superRightClick,
            selectionCapture: SelectionCaptureService(
                pasteboard: SystemPasteboardClient(),
                eventSender: SystemPasteEventSender()
            ),
            classifier: ClipboardClassifier(),
            translationService: TranslationService(
                provider: BaiduTranslationProvider(configuration: nil)
            )
        ),
        logger: logger,
        onItemCaptured: { [weak self] item in
            self?.handleSuperRightClickItem(item)
        }
    )

    init() {
        let supportDirectory = Self.applicationSupportDirectory()
        self.settingsStore = SettingsStore(
            fileURL: supportDirectory.appendingPathComponent("settings.json")
        )
        self.settings = (try? settingsStore.load()) ?? .defaults

        let database: ClipboardDatabase
        do {
            database = try ClipboardDatabase.at(
                supportDirectory.appendingPathComponent("Clipboard.sqlite")
            )
        } catch {
            logger.error("database open failed, using in-memory store: \(error)")
            database = try! ClipboardDatabase.inMemory()
        }

        let repository = ClipboardRepository(database: database)
        self.repository = repository
        self.pasteActionService = PasteActionService(
            pasteboard: SystemWritablePasteboard(),
            eventSender: SystemPasteEventSender()
        )
        self.clipboardService = ClipboardService(
            pasteboard: SystemPasteboardClient(),
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: settings,
            fileCache: FileCache(
                rootDirectory: supportDirectory.appendingPathComponent("ClipboardCache")
            )
        )
    }

    func start() {
        mainPanelDismissHandler.onDismiss = { [weak self] in
            self?.mainPanel.hide()
        }
        startClipboardPolling()
        superRightClickMonitor.start()
    }

    func openMainPanel() {
        captureFrontmostApplicationBeforePanel()
        mainPanelRouter.open(.settings)
        mainPanel.show()
    }

    func openClipboard() {
        captureFrontmostApplicationBeforePanel()
        clipboardModel.prepareForPresentation()
        mainPanelRouter.open(.clipboard)
        mainPanel.show()
    }

    func openSettings() {
        openMainPanel()
    }

    private func startClipboardPolling() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollClipboardOnce()
            }
        }
    }

    private func pollClipboardOnce() {
        do {
            try clipboardService.pollOnce(sourceApp: NSWorkspace.shared.frontmostApplication?.localizedName)
            clipboardModel.refresh()
        } catch {
            logger.error("clipboard poll failed: \(error)")
        }
    }

    private func captureFrontmostApplicationBeforePanel() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard frontmostApplication?.processIdentifier != ownProcessIdentifier else {
            logger.info("frontmost app is MacTools; keeping previous paste target")
            return
        }

        appBeforePanel = frontmostApplication
        logger.info("captured paste target: \(frontmostApplication?.localizedName ?? "unknown")")
    }

    private func copyFromPanel(_ item: ClipboardItem) {
        do {
            try clipboardModel.copy(item)
        } catch {
            logger.error("clipboard copy failed: \(error)")
        }
    }

    private func pasteFromPanel(_ item: ClipboardItem) {
        do {
            try clipboardModel.copy(item)
        } catch {
            logger.error("clipboard copy before paste failed: \(error)")
            return
        }

        guard canPostPasteEvent() else {
            logger.error("paste failed: missing post event permission")
            showPostEventRequiredAlert()
            return
        }

        let targetApplication = appBeforePanel
        mainPanel.hide()
        pasteAfterActivatingTarget(targetApplication)
    }

    private func pasteAfterActivatingTarget(_ targetApplication: NSRunningApplication?) {
        guard let targetApplication else {
            logger.error("paste target missing; sending paste after fallback delay")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.clipboardModel.paste()
            }
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        var observer: NSObjectProtocol?
        var didPaste = false

        func pasteOnce(reason: String) {
            guard !didPaste else {
                return
            }

            didPaste = true
            if let observer {
                notificationCenter.removeObserver(observer)
            }

            logger.info("sending paste to \(targetApplication.localizedName ?? "unknown") via \(reason)")
            clipboardModel.paste()
        }

        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let activatedApplication = notification
                .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard activatedApplication?.processIdentifier == targetApplication.processIdentifier else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                pasteOnce(reason: "activation notification")
            }
        }

        targetApplication.unhide()
        targetApplication.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            pasteOnce(reason: "activation timeout fallback")
        }
    }

    private func canPostPasteEvent() -> Bool {
        let summary = permissionService.summary()
        if summary.canPasteAutomatically {
            return true
        }

        return permissionService.requestPostEventPermission()
    }

    private func handleSuperRightClickItem(_ item: ClipboardItem) {
        switch item.kind {
        case .text:
            logger.info("translation requested; baidu provider is not configured")
            showTranslationUnavailableAlert()
        case .file, .folder, .imageFile:
            contextPanel.show(item: item)
        case .url, .imageData, .unknown:
            logger.info("no context actions for \(item.kind.rawValue)")
        }
    }

    private func showTranslationUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "翻译未配置"
        alert.informativeText = "百度翻译凭证还没有配置。"
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showPostEventRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "需要自动粘贴权限"
        alert.informativeText = "内容已复制到剪贴板。自动粘贴需要把 Command+V 发送到当前应用，请在系统设置里允许 MacTools 发送键盘事件。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            permissionService.openSystemSettings(for: .postEvent)
        }
    }

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("MacTools", isDirectory: true)
    }
}
