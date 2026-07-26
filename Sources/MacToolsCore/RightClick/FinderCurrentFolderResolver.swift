// `FinderCurrentFolderResolver` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import AppKit
import ApplicationServices
import Darwin
import Foundation

/// 定义 `FinderCurrentFolderResolving` 在超级右键领域中需要满足的能力边界。
public protocol FinderCurrentFolderResolving: Sendable {
    /// 异步读取并返回 `currentFolderURL` 对应的超级右键领域数据。
    func currentFolderURL(processIdentifier: Int32?) async -> URL?
}

/// 描述 `FinderDocumentURLParser` 在超级右键领域中可取的状态、选项或错误。
public enum FinderDocumentURLParser {
    /// 计算并返回 `fileURL` 对应的超级右键领域数据或状态结果。
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

/// 描述 `FinderAccessibilityDocumentResult` 在超级右键领域中可取的状态、选项或错误。
enum FinderAccessibilityDocumentResult {
    case noWindow
    case value(CFTypeRef)
    case unavailable
}

/// 描述 `FinderWindowLookupClassification` 在超级右键领域中可取的状态、选项或错误。
enum FinderWindowLookupClassification: Equatable {
    case available
    case noWindow
    case unavailable

    /// 根据输入特征判定 `classify` 对应的超级右键领域分类或处理决策。
    static func classify(error: AXError, windowCount: Int?) -> Self {
        guard error == .success,
              let windowCount,
              windowCount >= 0 else {
            return .unavailable
        }

        return windowCount == 0 ? .noWindow : .available
    }
}

/// 描述 `FinderScriptingProcessResult` 在超级右键领域中可取的状态、选项或错误。
enum FinderScriptingProcessResult: Equatable {
    case success(String)
    case launchFailure
    case nonzeroStatus(Int32)
    case timeout
    case cancellation
    case invalidOutput
}

/// 封装 `FinderScriptingProcessRunner` 在超级右键领域中的值语义和相关操作。
struct FinderScriptingProcessRunner: Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let timeout: TimeInterval
    private let terminationGracePeriod: TimeInterval
    private let state = State()

    /// 创建 `FinderScriptingProcessRunner`，保存传入依赖并建立初始状态。
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

    /// 在独立任务中运行脚本进程，并把取消、超时和退出状态归一化为结果枚举。
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

    /// 判断 `cancel` 所描述的超级右键领域条件是否成立。
    private func cancel() {
        state.cancel()
    }

    /// 运行 `runSynchronously` 对应的超级右键领域流程，直到完成或进入下一调度点。
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

    /// 协调子进程结束与资源回收，避免取消路径遗留运行中的进程。
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

    /// 执行 `sendSignal` 对应的超级右键领域输入输出操作。
    private static func sendSignal(_ signal: Int32, toProcessTreeRootedAt root: pid_t) {
        for descendant in descendants(of: root).reversed() {
            _ = Darwin.kill(descendant, signal)
        }
        _ = Darwin.kill(root, signal)
    }

    /// 计算并返回 `descendants` 对应的超级右键领域数据或状态结果。
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

    // NSLock 保护不可 Sendable 的 Process 引用和取消信号交接。
    /// 管理 `State` 在超级右键领域中的生命周期、依赖和可变状态。
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private let processCompletion = DispatchSemaphore(value: 0)
        private var cancellationRequested = false
        private var activeProcess: Process?

        var isCancellationRequested: Bool {
            lock.withLock { cancellationRequested }
        }

        /// 启动 `register` 对应的超级右键领域流程，并建立所需资源。
        func register(_ process: Process) -> Bool {
            lock.withLock {
                guard !cancellationRequested else {
                    return false
                }
                activeProcess = process
                return true
            }
        }

        /// 移除 `clear` 指定的超级右键领域数据，并维护关联状态。
        func clear(_ process: Process) {
            lock.withLock {
                if activeProcess === process {
                    activeProcess = nil
                }
            }
        }

        /// 判断 `cancel` 所描述的超级右键领域条件是否成立。
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

        /// 协调子进程结束与资源回收，避免取消路径遗留运行中的进程。
        func signalProcessCompletion() {
            processCompletion.signal()
        }

        /// 协调子进程结束与资源回收，避免取消路径遗留运行中的进程。
        func waitForProcessCompletion(until deadline: DispatchTime) -> DispatchTimeoutResult {
            processCompletion.wait(timeout: deadline)
        }
    }
}

/// 解析器在初始化后保持不可变；内部闭包一次只执行一个 Finder 请求。
public final class SystemFinderCurrentFolderResolver: FinderCurrentFolderResolving, @unchecked Sendable {
    private let desktopDirectory: URL
    private let accessibilityDocument: (Int32) -> FinderAccessibilityDocumentResult
    private let automationAuthorization: () async -> Bool
    private let scriptingDocument: () async -> String?

    /// 创建 `SystemFinderCurrentFolderResolver`，保存传入依赖并建立初始状态。
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

    /// 创建 `SystemFinderCurrentFolderResolver`，保存传入依赖并建立初始状态。
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

    /// 异步读取并返回 `currentFolderURL` 对应的超级右键领域数据。
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

    /// 在自动化授权通过后使用 Finder 脚本读取当前目录，并尊重任务取消。
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

    /// 计算并返回 `fileURL` 对应的超级右键领域数据或状态结果。
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

    /// 计算并返回 `systemAccessibilityDocument` 对应的超级右键领域数据或状态结果。
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

    /// 通过带超时的 `osascript` 查询 Finder 最前窗口目标 URL。
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

    /// 在后台线程查询对 Finder 发送 Apple Event 的当前授权状态。
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

    /// 描述 `FinderWindowLookupResult` 在超级右键领域中可取的状态、选项或错误。
    private enum FinderWindowLookupResult {
        case available(AXUIElement)
        case noWindow
        case unavailable
    }

    /// 更新 `focusedWindow` 对应的交互状态，并保持当前选择或展示约束。
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

    /// 封装 `FinderAttributeResult` 在超级右键领域中的值语义和相关操作。
    private struct FinderAttributeResult {
        let error: AXError
        let value: CFTypeRef?
    }

    /// 读取并返回 `copyAttribute` 对应的超级右键领域数据。
    private static func copyAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> FinderAttributeResult {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return FinderAttributeResult(error: result, value: value)
    }

    /// 发布或记录 `logScriptingFailure` 对应的超级右键领域状态。
    private static func logScriptingFailure(_ reason: String) {
        NSLog("ERROR finder current folder scripting fallback failed: %@", reason)
    }
}
