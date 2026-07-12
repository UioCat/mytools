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

enum FinderAccessibilityDocumentResult {
    case noWindow
    case value(CFTypeRef)
    case unavailable
}

public final class SystemFinderCurrentFolderResolver: FinderCurrentFolderResolving {
    private let desktopDirectory: URL
    private let accessibilityDocument: (Int32) -> FinderAccessibilityDocumentResult
    private let scriptingDocument: () -> String?

    public init(
        desktopDirectory: URL = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    ) {
        self.desktopDirectory = desktopDirectory
        accessibilityDocument = Self.systemAccessibilityDocument
        scriptingDocument = Self.systemScriptingDocument
    }

    init(
        desktopDirectory: URL,
        accessibilityDocument: @escaping (Int32) -> FinderAccessibilityDocumentResult,
        scriptingDocument: @escaping () -> String?
    ) {
        self.desktopDirectory = desktopDirectory
        self.accessibilityDocument = accessibilityDocument
        self.scriptingDocument = scriptingDocument
    }

    public func currentFolderURL(processIdentifier: Int32?) -> URL? {
        guard let processIdentifier else {
            return nil
        }

        switch accessibilityDocument(processIdentifier) {
        case .noWindow:
            return desktopDirectory
        case .value(let value):
            return fileURL(from: value) ?? scriptingDocument().flatMap(FinderDocumentURLParser.fileURL)
        case .unavailable:
            return scriptingDocument().flatMap(FinderDocumentURLParser.fileURL)
        }
    }

    private func fileURL(from documentValue: CFTypeRef) -> URL? {
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

    private static func systemAccessibilityDocument(
        processIdentifier: Int32
    ) -> FinderAccessibilityDocumentResult {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let window = focusedWindow(in: application) else {
            return .noWindow
        }
        guard let documentValue = copyAttribute(kAXDocumentAttribute, from: window) else {
            return .unavailable
        }

        return .value(documentValue)
    }

    private static func systemScriptingDocument() -> String? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return URL of target of front Finder window
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil,
              let document = result.stringValue,
              FinderDocumentURLParser.fileURL(from: document) != nil else {
            return nil
        }

        return document
    }

    private static func focusedWindow(in application: AXUIElement) -> AXUIElement? {
        if let window = copyElementAttribute(kAXFocusedWindowAttribute, from: application) {
            return window
        }

        guard let windows = copyAttribute(kAXWindowsAttribute, from: application) as? [AXUIElement] else {
            return nil
        }
        return windows.first
    }

    private static func copyElementAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copyAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func copyAttribute(
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
