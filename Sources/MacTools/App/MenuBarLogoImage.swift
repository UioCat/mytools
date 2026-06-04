import AppKit

enum MenuBarLogoImage {
    static func make() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let clipboard = NSBezierPath(roundedRect: NSRect(x: 5, y: 3.5, width: 12, height: 15), xRadius: 3, yRadius: 3)
        clipboard.lineWidth = 1.8
        clipboard.stroke()

        let clip = NSBezierPath(roundedRect: NSRect(x: 8, y: 15.5, width: 6, height: 3.5), xRadius: 1.6, yRadius: 1.6)
        clip.fill()

        let line1 = NSBezierPath()
        line1.move(to: NSPoint(x: 8.2, y: 11.7))
        line1.line(to: NSPoint(x: 13.8, y: 11.7))
        line1.lineWidth = 1.4
        line1.stroke()

        let line2 = NSBezierPath()
        line2.move(to: NSPoint(x: 8.2, y: 8.3))
        line2.line(to: NSPoint(x: 12.2, y: 8.3))
        line2.lineWidth = 1.4
        line2.stroke()

        let sparkle = NSBezierPath()
        sparkle.move(to: NSPoint(x: 17.2, y: 13.4))
        sparkle.line(to: NSPoint(x: 18.4, y: 10.6))
        sparkle.line(to: NSPoint(x: 21, y: 9.4))
        sparkle.line(to: NSPoint(x: 18.4, y: 8.2))
        sparkle.line(to: NSPoint(x: 17.2, y: 5.6))
        sparkle.line(to: NSPoint(x: 16, y: 8.2))
        sparkle.line(to: NSPoint(x: 13.4, y: 9.4))
        sparkle.line(to: NSPoint(x: 16, y: 10.6))
        sparkle.close()
        sparkle.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
