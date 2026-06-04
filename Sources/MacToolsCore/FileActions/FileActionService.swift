import AppKit
import Foundation

public protocol WorkspaceOpening {
    func open(_ url: URL)
    func reveal(_ url: URL)
}

public protocol ProcessRunning {
    func run(_ executableURL: URL, arguments: [String]) throws
}

public final class FileActionService {
    private let workspace: any WorkspaceOpening
    private let processRunner: any ProcessRunning
    private let fileManager: FileManager

    public init(
        workspace: any WorkspaceOpening,
        processRunner: any ProcessRunning = SystemProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public func copyPath(item: ClipboardItem, pasteboard: WritablePasteboard) throws {
        let path = try originalPath(for: item)
        pasteboard.writeText(path)
    }

    public func openTerminal(at folderPath: String) throws {
        guard isDirectory(at: folderPath) else {
            throw FileActionError.invalidFolderPath(folderPath)
        }

        try processRunner.run(
            URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", "Terminal", folderPath]
        )
    }

    public func terminalOpenCommand(for path: String) -> String {
        "open -a Terminal \(path)"
    }

    public func revealInFinder(_ item: ClipboardItem) throws {
        let path = try originalPath(for: item)
        workspace.reveal(URL(fileURLWithPath: path))
    }

    private func originalPath(for item: ClipboardItem) throws -> String {
        guard let path = item.originalPath else {
            throw FileActionError.missingPath
        }

        return path
    }

    private func isDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

public enum FileActionError: Error, Equatable {
    case missingPath
    case invalidFolderPath(String)
}

public final class SystemWorkspaceOpening: WorkspaceOpening {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func open(_ url: URL) {
        workspace.open(url)
    }

    public func reveal(_ url: URL) {
        workspace.activateFileViewerSelecting([url])
    }
}

public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executableURL: URL, arguments: [String]) throws {
        try Process.run(executableURL, arguments: arguments)
    }
}
