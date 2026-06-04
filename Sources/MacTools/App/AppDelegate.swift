import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private lazy var menuBarController = MenuBarController(environment: environment)

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.install()
        environment.logger.info("application did finish launching")
    }
}
