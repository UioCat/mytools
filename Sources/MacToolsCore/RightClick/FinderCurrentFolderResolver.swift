import AppKit
import ApplicationServices
import Foundation

public protocol FinderCurrentFolderResolving {
    func currentFolderURL(processIdentifier: Int32?) async -> URL?
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

enum FinderWindowLookupClassification: Equatable {
    case available
    case noWindow
    case unavailable

    static func classify(error: AXError, windowCount: Int?) -> Self {
        guard error == .success,
              let windowCount,
              windowCount >= 0 else {
            return .unavailable
        }

        return windowCount == 0 ? .noWindow : .available
    }
}

public final class SystemFinderCurrentFolderResolver: FinderCurrentFolderResolving {
    private let desktopDirectory: URL
    private let accessibilityDocument: (Int32) -> FinderAccessibilityDocumentResult
    private let scriptingDocument: () async -> String?

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
        scriptingDocument: @escaping () async -> String?
    ) {
        self.desktopDirectory = desktopDirectory
        self.accessibilityDocument = accessibilityDocument
        self.scriptingDocument = scriptingDocument
    }

    public func currentFolderURL(processIdentifier: Int32?) async -> URL? {
        guard let processIdentifier else {
            return nil
        }

        switch accessibilityDocument(processIdentifier) {
        case .noWindow:
            return desktopDirectory
        case .value(let value):
            if let url = fileURL(from: value) {
                return url
            }
            return await scriptingDocument().flatMap(FinderDocumentURLParser.fileURL)
        case .unavailable:
            return await scriptingDocument().flatMap(FinderDocumentURLParser.fileURL)
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
        switch focusedWindow(in: application) {
        case .available(let window):
            let document = copyAttribute(kAXDocumentAttribute, from: window)
            guard document.error == .success,
                  let documentValue = document.value else {
                return .unavailable
            }
            return .value(documentValue)
        case .noWindow:
            return .noWindow
        case .unavailable:
            return .unavailable
        }
    }

    private static func systemScriptingDocument() async -> String? {
        let source = """
        tell application "Finder"
            with timeout of 2 seconds
                if (count of Finder windows) is 0 then return ""
                return URL of target of front Finder window
            end timeout
        end tell
        """

        return await Task.detached(priority: .userInitiated) {
            runScriptingProcess(source: source)
        }.value
    }

    private static func runScriptingProcess(source: String) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let processFinished = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            processFinished.signal()
        }

        do {
            try process.run()
        } catch {
            logScriptingFailure("launch error")
            return nil
        }

        guard processFinished.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            logScriptingFailure("process timeout")
            return nil
        }

        guard process.terminationStatus == 0 else {
            logScriptingFailure("nonzero status \(process.terminationStatus)")
            return nil
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let rawDocument = String(data: output, encoding: .utf8) else {
            logScriptingFailure("invalid stdout encoding")
            return nil
        }

        let document = rawDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !document.isEmpty else {
            logScriptingFailure("empty output")
            return nil
        }
        guard FinderDocumentURLParser.fileURL(from: document) != nil else {
            logScriptingFailure("invalid URL")
            return nil
        }

        return document
    }

    private enum FinderWindowLookupResult {
        case available(AXUIElement)
        case noWindow
        case unavailable
    }

    private static func focusedWindow(in application: AXUIElement) -> FinderWindowLookupResult {
        let focusedWindow = copyAttribute(kAXFocusedWindowAttribute, from: application)
        if focusedWindow.error == .success {
            guard let value = focusedWindow.value,
                  CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return .unavailable
            }
            return .available(value as! AXUIElement)
        }

        let windowsAttribute = copyAttribute(kAXWindowsAttribute, from: application)
        let windows = windowsAttribute.value as? [AXUIElement]
        switch FinderWindowLookupClassification.classify(
            error: windowsAttribute.error,
            windowCount: windows?.count
        ) {
        case .available:
            guard let window = windows?.first else {
                return .unavailable
            }
            return .available(window)
        case .noWindow:
            return .noWindow
        case .unavailable:
            return .unavailable
        }
    }

    private struct FinderAttributeResult {
        let error: AXError
        let value: CFTypeRef?
    }

    private static func copyAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> FinderAttributeResult {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return FinderAttributeResult(error: result, value: value)
    }

    private static func logScriptingFailure(_ reason: String) {
        NSLog("ERROR finder current folder scripting fallback failed: %@", reason)
    }
}
