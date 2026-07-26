// `MenuBarController` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import AppKit

/// 管理 `MenuBarController` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class MenuBarController {
    private let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    /// 创建 `MenuBarController`，保存传入依赖并建立初始状态。
    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// 启动 `install` 对应的应用运行时与 AppKit 集成流程，并建立所需资源。
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

        let clipboardItem = NSMenuItem(title: "剪贴板", action: #selector(openClipboard), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)

        let screenCaptureItem = NSMenuItem(title: "截图与录屏", action: #selector(openScreenCapture), keyEquivalent: "")
        screenCaptureItem.target = self
        menu.addItem(screenCaptureItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    /// 展示 `open` 对应的应用运行时与 AppKit 集成界面或系统位置。
    @objc func open() {
        environment.logger.info("menu open selected")
        environment.openMainPanel()
    }

    /// 展示 `openSettings` 对应的应用运行时与 AppKit 集成界面或系统位置。
    @objc func openSettings() {
        environment.logger.info("menu settings selected")
        environment.openSettings()
    }

    /// 展示 `openClipboard` 对应的应用运行时与 AppKit 集成界面或系统位置。
    @objc func openClipboard() {
        environment.logger.info("menu clipboard selected")
        environment.openClipboard()
    }

    /// 展示 `openScreenCapture` 对应的应用运行时与 AppKit 集成界面或系统位置。
    @objc func openScreenCapture() {
        environment.logger.info("menu screen capture selected")
        environment.openScreenCapture()
    }
}
