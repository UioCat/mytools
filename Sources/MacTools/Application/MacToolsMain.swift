// MacTools 的 AppKit 进程入口。
// 负责配置辅助应用激活策略并启动主事件循环，不创建具体功能服务。

import AppKit

/// 管理 `MacToolsMain` 在应用入口中的生命周期、依赖和可变状态。
@main
@MainActor
final class MacToolsMain {
    /// 创建应用运行环境并启动 AppKit 主事件循环。
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        // 菜单栏辅助应用不显示 Dock 图标，也不主动接管前台应用焦点。
        app.setActivationPolicy(.accessory)
        // `NSApplication.delegate` 不负责强持有代理；显式延长生命周期，避免发布优化提前释放。
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
