import AppKit

enum MenuBarLogoImage {
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
