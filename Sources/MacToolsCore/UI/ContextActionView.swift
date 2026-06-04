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
                .foregroundStyle(.white)
                .lineLimit(1)

            actionButton(title: "复制路径", systemImage: "doc.on.doc", action: { copyPath(item) })

            if item.kind == .folder {
                actionButton(title: "在终端中打开", systemImage: "terminal", action: { openTerminal(item) })
            }

            if shouldShowRevealInFinder {
                actionButton(title: "在访达中显示", systemImage: "folder", action: { reveal(item) })
            }
        }
        .padding(14)
        .liquidGlassPanel(cornerRadius: 22)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(0.86))
        .liquidGlassModule(cornerRadius: 14)
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
