// 应用生命周期入口。
// 负责安装菜单栏、启动运行环境和热更新全局快捷键，不承载功能实现。

import AppKit
import MacToolsCore

/// 管理 `AppDelegate` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var environment = AppEnvironment()
    private let injectedShutdownCoordinator: ApplicationShutdownCoordinator?
    private lazy var shutdownCoordinator = injectedShutdownCoordinator ?? ApplicationShutdownCoordinator(
        stop: { [environment] in await environment.stop() },
        flush: { [environment] in environment.logger.flush() },
        reply: { NSApp.reply(toApplicationShouldTerminate: true) }
    )
    private lazy var menuBarController = MenuBarController(environment: environment)
    private lazy var hotKeyService = HotKeyService(registrar: CarbonHotKeyRegistrar())

    override init() {
        injectedShutdownCoordinator = nil
        super.init()
    }

    init(shutdownCoordinator: ApplicationShutdownCoordinator) {
        injectedShutdownCoordinator = shutdownCoordinator
        super.init()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shutdownCoordinator.requestTermination()
    }

    /// 按外观、菜单栏、环境服务和全局快捷键的顺序完成应用启动装配。
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let verificationAppearanceMode: AppAppearanceMode? = arguments.contains("--ui-verification-dark")
            ? .dark
            : nil
        configureAppearance(
            mode: verificationAppearanceMode ?? environment.settings.appearanceMode
        )
        NSApp.mainMenu = ApplicationMenu.makeMainMenu()
        menuBarController.install()
        environment.onValidateHotKeys = { [weak self] settings in
            guard let self else { return {} }
            let restore = try hotKeyService.configureForSave(settings: settings) { [weak self] target in
                self?.handleHotKey(target)
            }
            return { [weak self] in
                for failure in restore() {
                    self?.environment.logger.error("hotkey rollback failed: \(failure.hotKey.displayValue)")
                }
            }
        }
        environment.onSettingsChanged = { [weak self] settings in
            self?.configureHotKeys(settings: settings)
            self?.configureAppearance(
                mode: verificationAppearanceMode ?? settings.appearanceMode
            )
        }
        environment.start()
        configureHotKeys(settings: environment.settings)
        let shouldOpenSettingsForVerification = ProcessInfo.processInfo.environment[
            "MACTOOLS_UI_VERIFICATION_OPEN_SETTINGS"
        ] == "1" || arguments.contains("--ui-verification-open-settings")
        if shouldOpenSettingsForVerification {
            environment.logger.info("opening settings for UI verification")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.environment.openSettingsForUIVerification()
            }
        }
        if arguments.contains("--ui-verification-check-for-updates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.environment.checkForUpdatesForUIVerification()
            }
        }
        environment.logger.info("application did finish launching")
    }

    /// 关闭确认前已等待后台排空；最终退出再确保文件日志完成写入。
    func applicationWillTerminate(_ notification: Notification) {
        environment.logger.flush()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        environment.refreshSystemPermissions()
    }

    /// 使用最新设置整体重建全局快捷键注册，并把触发结果路由到运行环境。
    private func configureHotKeys(settings: AppSettings) {
        let failures = hotKeyService.configure(settings: settings) { [weak self] target in
            self?.handleHotKey(target)
        }
        for failure in failures {
            environment.logger.error("hotkey registration failed: \(failure.hotKey.displayValue)")
        }
    }

    /// 应用 `configureAppearance` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
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

    /// 将快捷键目标映射为面板、截图或窗口布局操作。
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
