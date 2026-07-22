import AppKit
import ApplicationServices
import Darwin
import Foundation

public protocol FinderCurrentFolderResolving: Sendable {
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

enum FinderScriptingProcessResult: Equatable {
    case success(String)
    case launchFailure
    case nonzeroStatus(Int32)
    case timeout
    case cancellation
    case invalidOutput
}

struct FinderScriptingProcessRunner: Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private let terminationGracePeriod: TimeInterval
    private let state = State()

    init(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        terminationGracePeriod: TimeInterval = 0.2
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
        self.terminationGracePeriod = terminationGracePeriod
    }

    func run() async -> FinderScriptingProcessResult {
        let worker = Task.detached(priority: .userInitiated) {
            runSynchronously()
        }

        return await withTaskCancellationHandler {
            let result = await worker.value
            return Task.isCancelled ? .cancellation : result
        } onCancel: {
            worker.cancel()
            cancel()
        }
    }

    private func cancel() {
        state.cancel()
    }

    private func runSynchronously() -> FinderScriptingProcessResult {
        guard !state.isCancellationRequested else {
            return .cancellation
        }

        let process = Process()
        let outputPipe = Pipe()
        let readingHandle = outputPipe.fileHandleForReading
        let writingHandle = outputPipe.fileHandleForWriting
        defer {
            try? readingHandle.close()
            try? writingHandle.close()
        }

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [state] _ in
            state.signalProcessCompletion()
        }

        do {
            try process.run()
            try? writingHandle.close()
        } catch {
            return state.isCancellationRequested ? .cancellation : .launchFailure
        }

        guard state.register(process) else {
            terminateAndReap(process)
            return .cancellation
        }

        let waitDeadline = DispatchTime.now() + timeout
        while process.isRunning && !state.isCancellationRequested {
            if state.waitForProcessCompletion(until: waitDeadline) == .timedOut {
                break
            }
        }

        if process.isRunning {
            let result: FinderScriptingProcessResult = state.isCancellationRequested
                ? .cancellation
                : .timeout
            terminateAndReap(process)
            return result
        }

        process.waitUntilExit()
        state.clear(process)
        guard !state.isCancellationRequested else {
            return .cancellation
        }
        guard process.terminationStatus == 0 else {
            return .nonzeroStatus(process.terminationStatus)
        }

        let output = readingHandle.readDataToEndOfFile()
        guard let rawDocument = String(data: output, encoding: .utf8) else {
            return .invalidOutput
        }

        let document = rawDocument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FinderDocumentURLParser.fileURL(from: document) != nil else {
            return .invalidOutput
        }
        return .success(document)
    }

    private func terminateAndReap(_ process: Process) {
        let processIdentifier = process.processIdentifier
        Self.sendSignal(SIGTERM, toProcessTreeRootedAt: processIdentifier)

        let graceDeadline = DispatchTime.now() + terminationGracePeriod
        while process.isRunning {
            if state.waitForProcessCompletion(until: graceDeadline) == .timedOut {
                break
            }
        }

        if process.isRunning {
            Self.sendSignal(SIGKILL, toProcessTreeRootedAt: processIdentifier)
        }
        process.waitUntilExit()
        state.clear(process)
    }

    private static func sendSignal(_ signal: Int32, toProcessTreeRootedAt root: pid_t) {
        for descendant in descendants(of: root).reversed() {
            _ = Darwin.kill(descendant, signal)
        }
        _ = Darwin.kill(root, signal)
    }

    private static func descendants(of processIdentifier: pid_t) -> [pid_t] {
        var pending = [processIdentifier]
        var descendants: [pid_t] = []

        while let parent = pending.popLast() {
            var children = Array(repeating: pid_t(0), count: 64)
            let reportedCount = children.withUnsafeMutableBytes { buffer in
                proc_listchildpids(parent, buffer.baseAddress, Int32(buffer.count))
            }
            guard reportedCount > 0 else {
                continue
            }

            let count = min(Int(reportedCount), children.count)
            let validChildren = children.prefix(count).filter { $0 > 0 }
            descendants.append(contentsOf: validChildren)
            pending.append(contentsOf: validChildren)
        }

        return descendants
    }

    // NSLock protects the non-Sendable Process reference and cancellation handoff.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private let processCompletion = DispatchSemaphore(value: 0)
        private var cancellationRequested = false
        private var activeProcess: Process?

        var isCancellationRequested: Bool {
            lock.withLock { cancellationRequested }
        }

        func register(_ process: Process) -> Bool {
            lock.withLock {
                guard !cancellationRequested else {
                    return false
                }
                activeProcess = process
                return true
            }
        }

        func clear(_ process: Process) {
            lock.withLock {
                if activeProcess === process {
                    activeProcess = nil
                }
            }
        }

        func cancel() {
            let process = lock.withLock {
                cancellationRequested = true
                return activeProcess?.isRunning == true ? activeProcess : nil
            }
            if let process {
                FinderScriptingProcessRunner.sendSignal(
                    SIGTERM,
                    toProcessTreeRootedAt: process.processIdentifier
                )
            }
            processCompletion.signal()
        }

        func signalProcessCompletion() {
            processCompletion.signal()
        }

        func waitForProcessCompletion(until deadline: DispatchTime) -> DispatchTimeoutResult {
            processCompletion.wait(timeout: deadline)
        }
    }
}

/// The resolver is immutable after initialization; its closures execute one request at a time.
public final class SystemFinderCurrentFolderResolver: FinderCurrentFolderResolving, @unchecked Sendable {
    private let desktopDirectory: URL
    private let accessibilityDocument: (Int32) -> FinderAccessibilityDocumentResult
    private let automationAuthorization: () async -> Bool
    private let scriptingDocument: () async -> String?

    public init(
        desktopDirectory: URL = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    ) {
        self.desktopDirectory = desktopDirectory
        accessibilityDocument = Self.systemAccessibilityDocument
        automationAuthorization = Self.systemAutomationAuthorization
        scriptingDocument = Self.systemScriptingDocument
    }

    init(
        desktopDirectory: URL,
        accessibilityDocument: @escaping (Int32) -> FinderAccessibilityDocumentResult,
        automationAuthorization: @escaping () async -> Bool,
        scriptingDocument: @escaping () async -> String?
    ) {
        self.desktopDirectory = desktopDirectory
        self.accessibilityDocument = accessibilityDocument
        self.automationAuthorization = automationAuthorization
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
            return await authorizedScriptingDocumentURL()
        case .unavailable:
            return await authorizedScriptingDocumentURL()
        }
    }

    private func authorizedScriptingDocumentURL() async -> URL? {
        guard await automationAuthorization() else {
            Self.logScriptingFailure("automation denied")
            return nil
        }
        guard !Task.isCancelled else {
            return nil
        }
        return await scriptingDocument().flatMap(FinderDocumentURLParser.fileURL)
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

        let result = await FinderScriptingProcessRunner(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", source],
            timeout: 3
        ).run()
        switch result {
        case .success(let document):
            return document
        case .launchFailure:
            logScriptingFailure("launch error")
        case .nonzeroStatus(let status):
            logScriptingFailure("nonzero status \(status)")
        case .timeout:
            logScriptingFailure("process timeout")
        case .cancellation:
            logScriptingFailure("process cancelled")
        case .invalidOutput:
            logScriptingFailure("invalid output")
        }
        return nil
    }

    private static func systemAutomationAuthorization() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            var target = AEAddressDesc()
            let bundleIdentifier = Data("com.apple.finder".utf8)
            let createStatus = bundleIdentifier.withUnsafeBytes { bytes in
                AECreateDesc(
                    DescType(typeApplicationBundleID),
                    bytes.baseAddress,
                    bytes.count,
                    &target
                )
            }
            guard createStatus == noErr else {
                return false
            }
            defer { AEDisposeDesc(&target) }

            return AEDeterminePermissionToAutomateTarget(
                &target,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                true
            ) == noErr
        }.value
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
