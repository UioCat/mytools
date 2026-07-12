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

        let textContent = SuperPanelContent.text(
            originalText: "super right click",
            translation: .success(
                TranslationResponse(translatedText: "超级右键点击", providerID: "snapshot")
            )
        )
        try writeSnapshot(
            ContextActionView(
                content: textContent,
                performAction: { _ in }
            ),
            content: textContent,
            to: outputDirectory.appendingPathComponent("super-panel-text.png")
        )

        let folderContent = SuperPanelContent.fileSystem(
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
        )
        try writeSnapshot(
            ContextActionView(
                content: folderContent,
                performAction: { _ in }
            ),
            content: folderContent,
            to: outputDirectory.appendingPathComponent("super-panel-folder.png")
        )
    }

    @MainActor
    private func writeSnapshot<V: View>(
        _ view: V,
        content: SuperPanelContent,
        to url: URL
    ) throws {
        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: view.padding(40))
            let panelSize = SuperPanelLayout.panelSize(for: content)
            renderer.scale = 2
            let renderedSize = CGSize(
                width: panelSize.width + 80,
                height: panelSize.height + 80
            )
            renderer.proposedSize = ProposedViewSize(
                width: renderedSize.width,
                height: renderedSize.height
            )

            guard let image = renderer.nsImage,
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                XCTFail("Could not render snapshot: \(url.path)")
                return
            }

            try pngData.write(to: url)
            XCTAssertEqual(bitmap.pixelsWide, Int(renderedSize.width * renderer.scale))
            XCTAssertEqual(bitmap.pixelsHigh, Int(renderedSize.height * renderer.scale))
            XCTAssertGreaterThan(pngData.count, 1_000)
        }
    }
}
