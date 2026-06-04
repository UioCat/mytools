import AppKit

final class MenuBarController {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "MT"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open", action: #selector(open), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc func open() {
        environment.logger.info("menu open selected")
    }
}
