import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(AppKit)
import AppKit
#endif

public protocol SelectionCapturing {
    func captureSelection() -> ClipboardPayload
}

public protocol SelectedTextReading {
    func readSelectedText() -> String?
}

public final class SelectionCaptureService: SelectionCapturing {
    private let pasteboard: PasteboardClient
    private let eventSender: PasteEventSender
    private let selectedTextReader: SelectedTextReading
    private let logger: Logger?

    public init(
        pasteboard: PasteboardClient,
        eventSender: PasteEventSender,
        selectedTextReader: SelectedTextReading = SystemSelectedTextReader(),
        logger: Logger? = nil
    ) {
        self.pasteboard = pasteboard
        self.eventSender = eventSender
        self.selectedTextReader = selectedTextReader
        self.logger = logger
    }

    public func captureSelection() -> ClipboardPayload {
        let accessibilityValue = selectedTextReader.readSelectedText()
        if let selectedText = Self.normalizedAccessibilityText(accessibilityValue) {
            logger?.info("selection capture read selected text via accessibility")
            return ClipboardPayload(text: selectedText)
        }
        if accessibilityValue != nil {
            logger?.info("selection capture ignored unusable accessibility text")
        }

        let changeCountBeforeCopy = pasteboard.changeCount
        logger?.info("selection capture falling back to copy shortcut")
        eventSender.sendCopyShortcut()
        Thread.sleep(forTimeInterval: 0.12)

        guard pasteboard.changeCount != changeCountBeforeCopy else {
            logger?.error("selection capture copy fallback produced no pasteboard change")
            return ClipboardPayload()
        }

        logger?.info("selection capture read payload from pasteboard after copy")
        return pasteboard.readPayload()
    }

    private static func normalizedAccessibilityText(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty,
              !normalized.unicodeScalars.contains(where: { $0.value == 0xFFFC }) else {
            return nil
        }
        return normalized
    }
}

public final class SystemSelectedTextReader: SelectedTextReading {
    public init() {}

    public func readSelectedText() -> String? {
        #if canImport(ApplicationServices)
        if let text = readSelectedText(from: AXUIElementCreateSystemWide()) {
            return text
        }

        #if canImport(AppKit)
        guard let processIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        return readSelectedText(from: AXUIElementCreateApplication(processIdentifier))
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }

    #if canImport(ApplicationServices)
    private func readSelectedText(from element: AXUIElement) -> String? {
        if let focusedElement = copyAXElementAttribute(kAXFocusedUIElementAttribute, from: element),
           let text = copySelectedText(from: focusedElement) {
            return text
        }

        return copySelectedText(from: element)
    }

    private func copySelectedText(from element: AXUIElement) -> String? {
        copyAttribute(kAXSelectedTextAttribute, from: element) as? String
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    private func copyAXElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element) else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }
    #endif
}
