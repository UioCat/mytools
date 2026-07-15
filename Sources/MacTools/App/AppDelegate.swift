import AppKit
import MacToolsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private lazy var menuBarController = MenuBarController(environment: environment)
    private lazy var hotKeyService = HotKeyService(registrar: CarbonHotKeyRegistrar())

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureAppearance(mode: environment.settings.appearanceMode)
        menuBarController.install()
        environment.onSettingsChanged = { [weak self] settings in
            self?.configureHotKeys(settings: settings)
            self?.configureAppearance(mode: settings.appearanceMode)
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

    private func configureAppearance(mode: AppAppearanceMode) {
        switch mode {
        case .followSystem:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
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
        case .screenCapture:
            environment.openScreenCapture()
        case .windowLayout(let mode):
            environment.applyWindowLayout(mode)
        }
    }
}
