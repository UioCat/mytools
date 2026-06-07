import AppKit
import ApplicationServices
import CoreGraphics
import MacToolsCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ windowID: UnsafeMutablePointer<CGWindowID>
) -> AXError

enum SystemWindowLayoutError: Error {
    case missingFrontmostApplication
    case missingFocusedWindow
    case missingWindowFrame
    case missingScreen
    case emptyLayoutButton
}

final class SystemWindowLayoutService {
    private struct AppliedLayout {
        var buttonID: String
        var mode: WindowLayoutMode
    }

    private let logger: Logger
    private var appliedLayoutsByWindowID: [CGWindowID: AppliedLayout] = [:]

    init(logger: Logger) {
        self.logger = logger
    }

    func apply(button: WindowLayoutButton) throws {
        let windowElement = try focusedWindowElement()
        let windowID = windowID(for: windowElement) ?? 0
        let previousMode = appliedLayoutsByWindowID[windowID]?.buttonID == button.id
            ? appliedLayoutsByWindowID[windowID]?.mode
            : nil
        guard let mode = button.mode(after: previousMode) else {
            throw SystemWindowLayoutError.emptyLayoutButton
        }

        let currentAXFrame = try frame(of: windowElement)
        let currentScreenFrame = currentAXFrame.flippedAcrossPrimaryScreen
        let screen = try screen(containing: currentScreenFrame)
        let targetFrame = WindowLayoutCalculator.targetFrame(for: mode, in: screen.visibleFrame)
        let targetAXFrame = targetFrame.flippedAcrossPrimaryScreen

        setFrame(targetAXFrame, for: windowElement)
        appliedLayoutsByWindowID[windowID] = AppliedLayout(buttonID: button.id, mode: mode)
        logger.info("applied window layout \(mode.rawValue) via button \(button.id)")
    }

    private func focusedWindowElement() throws -> AXUIElement {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            throw SystemWindowLayoutError.missingFrontmostApplication
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard
            let value = appElement.copyAttribute(kAXFocusedWindowAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            throw SystemWindowLayoutError.missingFocusedWindow
        }

        return (value as! AXUIElement)
    }

    private func frame(of windowElement: AXUIElement) throws -> CGRect {
        guard
            let position: CGPoint = windowElement.copyWrappedAttribute(kAXPositionAttribute),
            let size: CGSize = windowElement.copyWrappedAttribute(kAXSizeAttribute)
        else {
            throw SystemWindowLayoutError.missingWindowFrame
        }

        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, for windowElement: AXUIElement) {
        windowElement.setSizeAttribute(kAXSizeAttribute, frame.size)
        windowElement.setPointAttribute(kAXPositionAttribute, frame.origin)
        windowElement.setSizeAttribute(kAXSizeAttribute, frame.size)
    }

    private func screen(containing rect: CGRect) throws -> NSScreen {
        guard let screen = NSScreen.screens.max(by: { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }) else {
            throw SystemWindowLayoutError.missingScreen
        }

        return screen
    }

    private func windowID(for windowElement: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        let result = _AXUIElementGetWindow(windowElement, &windowID)
        return result == .success ? windowID : nil
    }
}

private extension AXUIElement {
    func copyAttribute(_ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }

    func copyWrappedAttribute<T>(_ attribute: String) -> T? {
        guard
            let value = copyAttribute(attribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }

        let success = AXValueGetValue(value as! AXValue, AXValueGetType(value as! AXValue), pointer)
        return success ? pointer.pointee : nil
    }

    func setPointAttribute(_ attribute: String, _ value: CGPoint) {
        var value = value
        guard let axValue = AXValueCreate(.cgPoint, &value) else {
            return
        }
        AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }

    func setSizeAttribute(_ attribute: String, _ value: CGSize) {
        var value = value
        guard let axValue = AXValueCreate(.cgSize, &value) else {
            return
        }
        AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }
}

private extension CGRect {
    var flippedAcrossPrimaryScreen: CGRect {
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY, !isNull else {
            return self
        }

        return CGRect(
            x: origin.x,
            y: primaryMaxY - maxY,
            width: width,
            height: height
        )
    }

    var area: CGFloat {
        guard !isNull else {
            return 0
        }
        return width * height
    }
}
