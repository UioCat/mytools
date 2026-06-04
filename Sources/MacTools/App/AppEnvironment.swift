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
        initialSize: NSSize(width: 900, height: 620),
        minimumSize: NSSize(width: 720, height: 480),
        rootView: RuntimeMainPanelView(
            model: clipboardModel,
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

    lazy var settingsPanel = MainPanelController(
        initialSize: NSSize(width: 720, height: 620),
        minimumSize: NSSize(width: 560, height: 460),
        rootView: RuntimeSettingsView(
            settings: settings,
            permissionService: permissionService
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
        clipboardModel.refresh()
        settingsPanel.hide()
        mainPanel.show()
    }

    func openSettings() {
        mainPanel.hide()
        settingsPanel.show()
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
            return
        }

        appBeforePanel = frontmostApplication
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

        mainPanel.hide()
        appBeforePanel?.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.clipboardModel.paste()
        }
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

    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("MacTools", isDirectory: true)
    }
}
