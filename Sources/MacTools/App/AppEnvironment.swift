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
    private var clipboardTimer: Timer?

    private lazy var clipboardModel = ClipboardPanelModel(
        repository: repository,
        pasteActionService: pasteActionService,
        logger: logger,
        limit: { [settings] in settings.clipboard.maxHistoryCount }
    )

    lazy var mainPanel = MainPanelController(
        rootView: RuntimeMainPanelView(model: clipboardModel)
    )

    lazy var settingsPanel = MainPanelController(
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
        startClipboardPolling()
        superRightClickMonitor.start()
    }

    func openMainPanel() {
        clipboardModel.refresh()
        mainPanel.show()
    }

    func openSettings() {
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
        alert.messageText = "Translation Not Configured"
        alert.informativeText = "Baidu translation credentials have not been configured yet."
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
