import AppKit
import Foundation

public protocol WorkspaceOpening {
    func open(_ url: URL)
    func reveal(_ url: URL)
}

public final class FileActionService {
    private let workspace: any WorkspaceOpening

    public init(workspace: any WorkspaceOpening) {
        self.workspace = workspace
    }

    public func copyPath(item: ClipboardItem, pasteboard: WritablePasteboard) throws {
        let path = try originalPath(for: item)
        pasteboard.writeText(path)
    }

    public func openTerminal(at folderPath: String) throws {
        try Process.run(
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
}

public enum FileActionError: Error, Equatable {
    case missingPath
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
