import AppKit

@MainActor
final class MenuBarController {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = ""
        item.button?.image = MenuBarLogoImage.make()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "剪贴工具"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开", action: #selector(open), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc func open() {
        environment.logger.info("menu open selected")
        environment.openMainPanel()
    }

    @objc func openSettings() {
        environment.logger.info("menu settings selected")
        environment.openSettings()
    }
}
