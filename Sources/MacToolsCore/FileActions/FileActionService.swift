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

    public func openExternalApplication(named applicationName: String, at path: String) throws {
        try processRunner.run(
            URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-a", applicationName, path]
        )
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
    case fileCreationFailed(String)
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
