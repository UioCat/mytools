import AppKit
import MacToolsCore
import SwiftUI

final class ContextPanelController {
    private let fileActionService: FileActionService
    private let pasteboard: WritablePasteboard
    private let logger: Logger
    private var panel: NSPanel?

    init(
        fileActionService: FileActionService,
        pasteboard: WritablePasteboard,
        logger: Logger
    ) {
        self.fileActionService = fileActionService
        self.pasteboard = pasteboard
        self.logger = logger
    }

    func show(item: ClipboardItem) {
        let view = ContextActionView(
            item: item,
            copyPath: { [weak self] item in
                self?.copyPath(item)
            },
            openTerminal: { [weak self] item in
                self?.openTerminal(item)
            },
            reveal: { [weak self] item in
                self?.reveal(item)
            }
        )

        if panel == nil {
            panel = makePanel()
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel?.contentView = hostingView
        panel?.setFrameOrigin(panelOrigin())
        panel?.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        return panel
    }

    private func panelOrigin() -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        return NSPoint(x: mouseLocation.x, y: mouseLocation.y - 180)
    }

    private func copyPath(_ item: ClipboardItem) {
        do {
            try fileActionService.copyPath(item: item, pasteboard: pasteboard)
        } catch {
            logger.error("copy path failed: \(error)")
        }
    }

    private func openTerminal(_ item: ClipboardItem) {
        do {
            guard let path = item.originalPath else {
                throw FileActionError.missingPath
            }
            try fileActionService.openTerminal(at: path)
        } catch {
            logger.error("open terminal failed: \(error)")
        }
    }

    private func reveal(_ item: ClipboardItem) {
        do {
            try fileActionService.revealInFinder(item)
        } catch {
            logger.error("reveal in finder failed: \(error)")
        }
    }
}
