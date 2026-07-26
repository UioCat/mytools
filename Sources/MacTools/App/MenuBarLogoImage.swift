// `MenuBarLogoImage` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import AppKit

/// 描述 `MenuBarLogoImage` 在应用运行时与 AppKit 集成中可取的状态、选项或错误。
enum MenuBarLogoImage {
    /// 构造并返回 `make` 所描述的应用运行时与 AppKit 集成对象。
    static func make() -> NSImage {
        let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png")
        guard let iconURL, let image = NSImage(contentsOf: iconURL) else {
            return NSImage(size: NSSize(width: 18, height: 18))
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }
}
