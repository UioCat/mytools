// `FileActionService` 的文件操作领域实现。
// 负责构建并执行文件动作，不管理 Finder 授权流程。

import AppKit
import Foundation

/// 定义 `WorkspaceOpening` 在文件操作领域中需要满足的能力边界。
public protocol WorkspaceOpening {
    /// 展示 `open` 对应的文件操作领域界面或系统位置。
    func open(_ url: URL)
    /// 展示 `reveal` 对应的文件操作领域界面或系统位置。
    func reveal(_ url: URL)
}

/// 定义 `ProcessRunning` 在文件操作领域中需要满足的能力边界。
public protocol ProcessRunning {
    /// 运行 `run` 对应的文件操作领域流程，直到完成或进入下一调度点。
    func run(_ executableURL: URL, arguments: [String]) throws
}

/// 管理 `FileActionService` 在文件操作领域中的生命周期、依赖和可变状态。
public final class FileActionService {
    private let workspace: any WorkspaceOpening
    private let processRunner: any ProcessRunning
    private let fileManager: FileManager

    /// 创建 `FileActionService`，保存传入依赖并建立初始状态。
    public init(
        workspace: any WorkspaceOpening,
        processRunner: any ProcessRunning = SystemProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    /// 执行 `copyPath` 对应的文件操作领域输入输出操作。
    public func copyPath(item: ClipboardItem, pasteboard: WritablePasteboard) throws {
        let path = try originalPath(for: item)
        pasteboard.writeText(path)
    }

    /// 展示 `openTerminal` 对应的文件操作领域界面或系统位置。
    public func openTerminal(at folderPath: String) throws {
        guard isDirectory(at: folderPath) else {
            throw FileActionError.invalidFolderPath(folderPath)
        }

        try processRunner.run(
            URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "Terminal", folderPath]
        )
    }

    /// 计算并返回 `terminalOpenCommand` 对应的文件操作领域数据或状态结果。
    public func terminalOpenCommand(for path: String) -> String {
        "open -a Terminal \(path)"
    }

    /// 展示 `revealInFinder` 对应的文件操作领域界面或系统位置。
    public func revealInFinder(_ item: ClipboardItem) throws {
        let path = try originalPath(for: item)
        workspace.reveal(URL(fileURLWithPath: path))
    }

    /// 构造并返回 `createNewFile` 所描述的文件操作领域对象。
    public func createNewFile(in item: ClipboardItem) throws -> URL {
        let path = try originalPath(for: item)
        let folderURL: URL

        if isDirectory(at: path) {
            folderURL = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folderURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            guard isDirectory(at: folderURL.path) else {
                throw FileActionError.invalidFolderPath(folderURL.path)
            }
        }

        for index in 1...1_000 {
            let fileName = index == 1 ? "Untitled.txt" : "Untitled \(index).txt"
            let fileURL = folderURL.appendingPathComponent(fileName, isDirectory: false)
            guard !fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            guard fileManager.createFile(atPath: fileURL.path, contents: Data()) else {
                throw FileActionError.fileCreationFailed(fileURL.path)
            }

            return fileURL
        }

        throw FileActionError.fileCreationFailed(folderURL.appendingPathComponent("Untitled.txt").path)
    }

    /// 展示 `openExternalApplication` 对应的文件操作领域界面或系统位置。
    public func openExternalApplication(named applicationName: String, at path: String) throws {
        try processRunner.run(
            URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", applicationName, path]
        )
    }

    /// 计算并返回 `originalPath` 对应的文件操作领域数据或状态结果。
    private func originalPath(for item: ClipboardItem) throws -> String {
        guard let path = item.originalPath else {
            throw FileActionError.missingPath
        }

        return path
    }

    /// 判断 `isDirectory` 所描述的文件操作领域条件是否成立。
    private func isDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// 描述 `FileActionError` 在文件操作领域中可取的状态、选项或错误。
public enum FileActionError: Error, Equatable {
    case missingPath
    case invalidFolderPath(String)
    case fileCreationFailed(String)
}

/// 管理 `SystemWorkspaceOpening` 在文件操作领域中的生命周期、依赖和可变状态。
public final class SystemWorkspaceOpening: WorkspaceOpening {
    private let workspace: NSWorkspace

    /// 创建 `SystemWorkspaceOpening`，保存传入依赖并建立初始状态。
    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    /// 展示 `open` 对应的文件操作领域界面或系统位置。
    public func open(_ url: URL) {
        workspace.open(url)
    }

    /// 展示 `reveal` 对应的文件操作领域界面或系统位置。
    public func reveal(_ url: URL) {
        workspace.activateFileViewerSelecting([url])
    }
}

/// 封装 `SystemProcessRunner` 在文件操作领域中的值语义和相关操作。
public struct SystemProcessRunner: ProcessRunning {
    /// 创建 `SystemProcessRunner`，保存传入依赖并建立初始状态。
    public init() {}

    /// 运行 `run` 对应的文件操作领域流程，直到完成或进入下一调度点。
    public func run(_ executableURL: URL, arguments: [String]) throws {
        try Process.run(executableURL, arguments: arguments)
    }
}
