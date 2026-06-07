import AppKit
import MacToolsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private lazy var menuBarController = MenuBarController(environment: environment)
    private lazy var hotKeyService = HotKeyService(registrar: CarbonHotKeyRegistrar())

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.install()
        environment.onSettingsChanged = { [weak self] settings in
            self?.configureHotKeys(settings: settings)
        }
        environment.start()
        configureHotKeys(settings: environment.settings)
        environment.logger.info("application did finish launching")
    }

    private func configureHotKeys(settings: AppSettings) {
        hotKeyService.configure(settings: settings) { [weak self] target in
            self?.handleHotKey(target)
        }
    }

    private func handleHotKey(_ target: HotKeyTarget) {
        switch target {
        case .mainPanel:
            environment.openSettings()
        case .clipboard:
            environment.openClipboard()
        case .translation:
            environment.openTranslation()
        case .reservedTool3:
            environment.logger.info("reserved hotkey selected: \(target.rawValue)")
        case .windowLayout(let mode):
            environment.applyWindowLayout(mode)
        }
    }
}
