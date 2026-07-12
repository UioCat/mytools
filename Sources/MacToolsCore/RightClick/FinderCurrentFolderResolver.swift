import AppKit
import ApplicationServices
import Foundation

public protocol FinderCurrentFolderResolving {
    func currentFolderURL(processIdentifier: Int32?) -> URL?
}

public enum FinderDocumentURLParser {
    public static func fileURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        }

        guard let url = URL(string: value), url.isFileURL else {
            return nil
        }

        return URL(fileURLWithPath: url.path, isDirectory: true).standardizedFileURL
    }
}

public final class SystemFinderCurrentFolderResolver: FinderCurrentFolderResolving {
    private let desktopDirectory: URL

    public init(
        desktopDirectory: URL = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    ) {
        self.desktopDirectory = desktopDirectory
    }

    public func currentFolderURL(processIdentifier: Int32?) -> URL? {
        guard let processIdentifier else {
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window = focusedWindow(in: application) else {
            return desktopDirectory
        }
        guard let documentValue = copyAttribute(kAXDocumentAttribute, from: window) else {
            return nil
        }

        if let documentURL = documentValue as? URL, documentURL.isFileURL {
            return URL(
                fileURLWithPath: documentURL.path,
                isDirectory: true
            ).standardizedFileURL
        }
        guard let document = documentValue as? String else {
            return nil
        }

        return FinderDocumentURLParser.fileURL(from: document)
    }

    private func focusedWindow(in application: AXUIElement) -> AXUIElement? {
        if let window = copyElementAttribute(kAXFocusedWindowAttribute, from: application) {
            return window
        }

        guard let windows = copyAttribute(kAXWindowsAttribute, from: application) as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }

    private func copyElementAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copyAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value
    }
}
