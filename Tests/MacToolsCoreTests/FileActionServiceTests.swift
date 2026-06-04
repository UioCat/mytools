import Foundation
import XCTest
@testable import MacToolsCore

final class FileActionServiceTests: XCTestCase {
    func testTerminalOpenCommandUsesBuiltInTerminal() {
        let service = FileActionService(workspace: FakeWorkspaceOpening())

        let command = service.terminalOpenCommand(for: "/Users/example/Project")

        XCTAssertEqual(command, "open -a Terminal /Users/example/Project")
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
    }

    private(set) var operations: [Operation] = []

    func writeText(_ text: String) {
        operations.append(.writeText(text))
    }

    func writeFileURL(_ url: URL) {
        operations.append(.writeFileURL(url))
    }
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
