// 应用生命周期入口。
// 负责安装菜单栏、启动运行环境和热更新全局快捷键，不承载功能实现。

import AppKit
import MacToolsCore

/// 管理 `AppDelegate` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let environment = AppEnvironment()
    private lazy var menuBarController = MenuBarController(environment: environment)
    private lazy var hotKeyService = HotKeyService(registrar: CarbonHotKeyRegistrar())

    /// 按外观、菜单栏、环境服务和全局快捷键的顺序完成应用启动装配。
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let usesDarkVerificationAppearance = arguments.contains("--ui-verification-dark")
        configureAppearance(
            mode: usesDarkVerificationAppearance ? .dark : environment.settings.appearanceMode
        )
        menuBarController.install()
        environment.onSettingsChanged = { [weak self] settings in
            self?.configureHotKeys(settings: settings)
            self?.configureAppearance(mode: settings.appearanceMode)
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
        environment.logger.info("application did finish launching")
    }

    /// 响应 `applicationWillTerminate` 对应的应用生命周期事件，并同步运行时服务状态。
    func applicationWillTerminate(_ notification: Notification) {
        environment.logger.flush()
    }

    /// 使用最新设置整体重建全局快捷键注册，并把触发结果路由到运行环境。
    private func configureHotKeys(settings: AppSettings) {
        hotKeyService.configure(settings: settings) { [weak self] target in
            self?.handleHotKey(target)
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
