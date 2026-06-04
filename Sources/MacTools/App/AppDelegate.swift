import AppKit
import MacToolsCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private lazy var menuBarController = MenuBarController(environment: environment)
    private lazy var hotKeyService = HotKeyService(registrar: CarbonHotKeyRegistrar())

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.install()
        hotKeyService.configure(settings: .defaults) { [weak self] target in
            self?.handleHotKey(target)
        }
        environment.logger.info("application did finish launching")
    }

    private func handleHotKey(_ target: HotKeyTarget) {
        switch target {
        case .mainPanel, .clipboard:
            environment.mainPanel.show()
        case .reservedTool2, .reservedTool3:
            environment.logger.info("reserved hotkey selected: \(target.rawValue)")
        }
    }
}
