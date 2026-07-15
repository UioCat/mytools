import AppKit
import MacToolsCore

@MainActor
final class RecordingControlPanelController {
    private var panel: NSPanel?
    private var elapsedLabel: NSTextField?
    private var startedAt: Date?
    private var timer: Timer?
    private var onStop: (() -> Void)?

    func show(selection: ScreenCaptureSelection, onStop: @escaping () -> Void) {
        hide()
        self.onStop = onStop
        startedAt = .now

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 16
        effectView.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: "正在录制")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor

        let elapsedLabel = NSTextField(labelWithString: "00:00")
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        elapsedLabel.textColor = .secondaryLabelColor
        self.elapsedLabel = elapsedLabel

        let stopButton = NSButton(title: "停止", target: self, action: #selector(stopRecording))
        stopButton.bezelStyle = .texturedRounded
        stopButton.contentTintColor = .systemRed
        stopButton.font = .systemFont(ofSize: 13, weight: .semibold)
        stopButton.setAccessibilityLabel("停止录屏")

        let stack = NSStackView(views: [title, elapsedLabel, stopButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 10)
        effectView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        let visibleFrame = NSScreen.screens.first(where: { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            return (screen.deviceDescription[key] as? NSNumber)?.uint32Value == selection.displayID
        })?.visibleFrame ?? selection.displayFrame
        let panelFrame = ScreenCaptureOverlayLayout.recordingControlFrame(visibleFrame: visibleFrame)
        let panel = RecordingControlPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = effectView
        panel.orderFrontRegardless()
        self.panel = panel

        updateElapsedLabel()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsedLabel()
            }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        elapsedLabel = nil
        startedAt = nil
        onStop = nil
    }

    private func updateElapsedLabel() {
        guard let startedAt else {
            return
        }
        let elapsedSeconds = Int(Date.now.timeIntervalSince(startedAt))
        elapsedLabel?.stringValue = String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    @objc private func stopRecording() {
        let handler = onStop
        onStop = nil
        handler?()
    }
}

private final class RecordingControlPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
