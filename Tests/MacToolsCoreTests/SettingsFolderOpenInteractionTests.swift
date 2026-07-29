import Foundation
import XCTest
@testable import MacToolsCore

final class SettingsFolderOpenInteractionTests: XCTestCase {
    func testSyncFolderOpenDecisionRequiresASelectedFolder() {
        var openCount = 0

        XCTAssertEqual(
            FolderOpenInteraction.openSyncFolder(
                folderPath: nil,
                openFolder: { openCount += 1 }
            ),
            .showFolderSelectionRequired
        )
        XCTAssertEqual(openCount, 0)

        XCTAssertEqual(
            FolderOpenInteraction.openSyncFolder(
                folderPath: "/tmp/MacTools Sync",
                openFolder: { openCount += 1 }
            ),
            .openFolder
        )
        XCTAssertEqual(openCount, 1)
    }

    func testSyncFolderOpenDecisionTreatsBlankPathsAsUnconfigured() {
        var openCount = 0

        for folderPath in ["", "   \n"] {
            XCTAssertEqual(
                FolderOpenInteraction.openSyncFolder(
                    folderPath: folderPath,
                    openFolder: { openCount += 1 }
                ),
                .showFolderSelectionRequired
            )
        }

        XCTAssertEqual(openCount, 0)
    }

    func testUnifiedStorageUsesInjectedFinderOpenAction() throws {
        var openCount = 0
        FolderOpenInteraction.openClipboardStorage {
            openCount += 1
        }
        XCTAssertEqual(openCount, 1)

        let settingsSource = try source(at: "Sources/MacToolsCore/UI/Settings/SettingsView.swift")
        let clipboardSettingsSource = try source(
            at: "Sources/MacToolsCore/UI/Settings/ClipboardSettingsEditor.swift"
        )
        let runtimeSource = try source(at: "Sources/MacTools/Application/RuntimeViews.swift")
        let environmentSource = try source(at: "Sources/MacTools/Application/AppEnvironment.swift")

        XCTAssertTrue(clipboardSettingsSource.contains("Image(systemName: \"folder\")"))
        XCTAssertTrue(clipboardSettingsSource.contains(".help(\"打开统一存储文件夹\")"))
        XCTAssertTrue(settingsSource.contains("openStorageFolder: openClipboardStorageFolder"))
        XCTAssertTrue(runtimeSource.contains("openClipboardStorageFolder: onOpenClipboardStorageFolder"))
        XCTAssertTrue(environmentSource.contains("NSWorkspace.shared.open(defaultClipboardCacheDirectory)"))
    }

    private func source(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
