import Foundation
import SwiftUI
import XCTest
@testable import MacToolsCore

final class SuperPanelSnapshotTests: XCTestCase {
    @MainActor
    func testWriteSuperPanelSnapshotsWhenRequested() throws {
        guard let outputDirectoryPath = ProcessInfo.processInfo.environment["MACTOOLS_SUPER_PANEL_SNAPSHOT_DIR"] else {
            return
        }

        let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try writeSnapshot(
            ContextActionView(
                content: .text(
                    originalText: "super right click",
                    translation: .success(
                        TranslationResponse(translatedText: "超级右键点击", providerID: "snapshot")
                    )
                ),
                performAction: { _ in }
            ),
            to: outputDirectory.appendingPathComponent("super-panel-text.png")
        )

        try writeSnapshot(
            ContextActionView(
                content: .fileSystem(
                    item: ClipboardItem(
                        id: UUID(),
                        kind: .folder,
                        displayTitle: "linux-6.10",
                        searchableText: "/Users/example/Downloads/linux-6.10",
                        text: nil,
                        originalPath: "/Users/example/Downloads/linux-6.10",
                        cachedFilePath: nil,
                        thumbnailPath: nil,
                        sourceApp: "访达",
                        createdAt: Date(timeIntervalSince1970: 0),
                        lastUsedAt: nil,
                        useCount: 0,
                        isPinned: false,
                        isFavorite: false
                    )
                ),
                performAction: { _ in }
            ),
            to: outputDirectory.appendingPathComponent("super-panel-folder.png")
        )
    }

    @MainActor
    private func writeSnapshot<V: View>(_ view: V, to url: URL) throws {
        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: view.padding(40))
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 620, height: nil)

            guard let image = renderer.nsImage,
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                XCTFail("Could not render snapshot: \(url.path)")
                return
            }

            try pngData.write(to: url)
            XCTAssertGreaterThan(pngData.count, 10_000)
        }
    }
}
