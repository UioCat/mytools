import SwiftUI

public struct ContextActionView: View {
    public let item: ClipboardItem
    private let copyPath: (ClipboardItem) -> Void
    private let openTerminal: (ClipboardItem) -> Void
    private let reveal: (ClipboardItem) -> Void

    public init(
        item: ClipboardItem,
        copyPath: @escaping (ClipboardItem) -> Void,
        openTerminal: @escaping (ClipboardItem) -> Void,
        reveal: @escaping (ClipboardItem) -> Void
    ) {
        self.item = item
        self.copyPath = copyPath
        self.openTerminal = openTerminal
        self.reveal = reveal
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Button("Copy Path") {
                copyPath(item)
            }

            if item.kind == .folder {
                Button("Open in Terminal") {
                    openTerminal(item)
                }
            }

            if shouldShowRevealInFinder {
                Button("Reveal in Finder") {
                    reveal(item)
                }
            }
        }
        .padding(12)
    }

    private var shouldShowRevealInFinder: Bool {
        switch item.kind {
        case .file, .imageFile:
            return true
        case .text, .url, .folder, .imageData, .unknown:
            return false
        }
    }
}
