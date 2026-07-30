import Foundation
import XCTest
@testable import MacToolsCore

final class FileActionServiceTests: XCTestCase {
    func testCopyPathPropagatesPasteboardWriteFailure() {
        let pasteboard = FakeWritablePasteboard()
        pasteboard.writeError = FileActionTestError.expectedFailure
        let service = FileActionService(workspace: FakeWorkspaceOpening())

        XCTAssertThrowsError(
            try service.copyPath(
                item: .testItem(kind: .file, originalPath: "/tmp/report.pdf"),
                pasteboard: pasteboard
            )
        ) { error in
            XCTAssertEqual(error as? FileActionTestError, .expectedFailure)
        }
    }

    func testOpenTerminalRunsBuiltInTerminalForFolderPath() throws {
        let processRunner = FakeProcessRunner()
        let folderURL = temporaryFolderURL()
        let service = FileActionService(workspace: FakeWorkspaceOpening(), processRunner: processRunner)

        try service.openTerminal(at: folderURL.path)

        XCTAssertEqual(
            processRunner.runs,
            [.init(executableURL: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Terminal", folderURL.path])]
        )
    }

    func testOpenTerminalRejectsMissingFolderPath() {
        let processRunner = FakeProcessRunner()
        let missingPath = temporaryFolderURL().appendingPathComponent("missing").path
        let service = FileActionService(workspace: FakeWorkspaceOpening(), processRunner: processRunner)

        XCTAssertThrowsError(try service.openTerminal(at: missingPath)) { error in
            XCTAssertEqual(error as? FileActionError, .invalidFolderPath(missingPath))
        }
        XCTAssertTrue(processRunner.runs.isEmpty)
    }

    func testOpenTerminalRejectsFilePath() throws {
        let processRunner = FakeProcessRunner()
        let fileURL = temporaryFolderURL().appendingPathComponent("report.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        let service = FileActionService(workspace: FakeWorkspaceOpening(), processRunner: processRunner)

        XCTAssertThrowsError(try service.openTerminal(at: fileURL.path)) { error in
            XCTAssertEqual(error as? FileActionError, .invalidFolderPath(fileURL.path))
        }
        XCTAssertTrue(processRunner.runs.isEmpty)
    }

    func testCopyPathWritesOriginalPathAsText() throws {
        let pasteboard = FakeWritablePasteboard()
        let service = FileActionService(workspace: FakeWorkspaceOpening())

        try service.copyPath(item: .testItem(kind: .file, originalPath: "/tmp/report.pdf"), pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.operations, [.writeText("/tmp/report.pdf")])
    }

    func testCopyPathThrowsMissingPathWhenOriginalPathIsMissing() {
        let pasteboard = FakeWritablePasteboard()
        let service = FileActionService(workspace: FakeWorkspaceOpening())

        XCTAssertThrowsError(try service.copyPath(item: .testItem(kind: .file), pasteboard: pasteboard)) { error in
            XCTAssertEqual(error as? FileActionError, .missingPath)
        }
        XCTAssertTrue(pasteboard.operations.isEmpty)
    }

    func testRevealInFinderDelegatesToWorkspaceWithOriginalPath() throws {
        let workspace = FakeWorkspaceOpening()
        let service = FileActionService(workspace: workspace)

        try service.revealInFinder(.testItem(kind: .imageFile, originalPath: "/tmp/screenshot.png"))

        XCTAssertEqual(workspace.revealedURLs, [URL(fileURLWithPath: "/tmp/screenshot.png")])
    }

    func testRevealInFinderThrowsMissingPathWhenOriginalPathIsMissing() {
        let workspace = FakeWorkspaceOpening()
        let service = FileActionService(workspace: workspace)

        XCTAssertThrowsError(try service.revealInFinder(.testItem(kind: .folder))) { error in
            XCTAssertEqual(error as? FileActionError, .missingPath)
        }
        XCTAssertTrue(workspace.revealedURLs.isEmpty)
    }

    func testCreateNewFileCreatesUntitledFileInsideFolder() throws {
        let folderURL = temporaryFolderURL()
        let service = FileActionService(workspace: FakeWorkspaceOpening())

        let fileURL = try service.createNewFile(in: .testItem(kind: .folder, originalPath: folderURL.path))

        XCTAssertEqual(fileURL.lastPathComponent, "Untitled.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCreateNewFileUsesNextAvailableName() throws {
        let folderURL = temporaryFolderURL()
        FileManager.default.createFile(
            atPath: folderURL.appendingPathComponent("Untitled.txt").path,
            contents: Data()
        )
        let service = FileActionService(workspace: FakeWorkspaceOpening())

        let fileURL = try service.createNewFile(in: .testItem(kind: .folder, originalPath: folderURL.path))

        XCTAssertEqual(fileURL.lastPathComponent, "Untitled 2.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testOpenExternalApplicationRunsOpenWithApplicationNameAndPath() throws {
        let processRunner = FakeProcessRunner()
        let service = FileActionService(workspace: FakeWorkspaceOpening(), processRunner: processRunner)

        try service.openExternalApplication(named: "Claude", at: "/Users/example/Project")

        XCTAssertEqual(
            processRunner.runs,
            [.init(executableURL: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "Claude", "/Users/example/Project"])]
        )
    }
}

private final class FakeWorkspaceOpening: WorkspaceOpening {
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }
}

private final class FakeWritablePasteboard: WritablePasteboard {
    enum Operation: Equatable {
        case writeText(String)
        case writeFileURL(URL)
        case writeImageData(Data)
    }

    var writeError: Error?
    private(set) var operations: [Operation] = []

    func writeText(_ text: String) throws {
        if let writeError { throw writeError }
        operations.append(.writeText(text))
    }

    func writeFileURL(_ url: URL) {
        operations.append(.writeFileURL(url))
    }

    func writeImageData(_ data: Data) {
        operations.append(.writeImageData(data))
    }
}

private enum FileActionTestError: Error {
    case expectedFailure
}

private final class FakeProcessRunner: ProcessRunning {
    struct Run: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    private(set) var runs: [Run] = []

    func run(_ executableURL: URL, arguments: [String]) throws {
        runs.append(.init(executableURL: executableURL, arguments: arguments))
    }
}

private func temporaryFolderURL() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacToolsCoreTests")
        .appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension ClipboardItem {
    static func testItem(
        kind: ClipboardContentKind,
        originalPath: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: originalPath ?? "Missing Path",
            searchableText: originalPath ?? "",
            text: nil,
            originalPath: originalPath,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: "Tests",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }
}
