// `MacToolsMain` 的应用入口实现。
// 负责装配运行环境并启动 AppKit 事件循环，不实现具体业务能力。

import AppKit

/// 管理 `MacToolsMain` 在应用入口中的生命周期、依赖和可变状态。
@main
@MainActor
final class MacToolsMain {
    /// 创建应用运行环境并启动 AppKit 主事件循环。
    static func main() {
        let app = NSApplication.shared
        // `run()` 在当前调用栈内持续运行，因此局部变量会在整个事件循环期间持有代理。
        let delegate = AppDelegate()

        app.delegate = delegate
        // 菜单栏辅助应用不显示 Dock 图标，也不主动接管前台应用焦点。
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
