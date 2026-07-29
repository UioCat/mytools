// 录屏期间悬浮控制面板的 AppKit 实现。
// 负责展示录制状态和停止入口，不拥有 ScreenCaptureKit 会话。

import AppKit
import MacToolsCore
import SwiftUI

/// 承载录屏控制条的可观察计时状态，由 AppKit 生命周期控制器更新。
@MainActor
private final class RecordingControlState: ObservableObject {
    @Published var elapsedText = "00:00"
}

/// 管理 `RecordingControlPanelController` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
@MainActor
final class RecordingControlPanelController {
    private var panel: NSPanel?
    private var controlState: RecordingControlState?
    private var startedAt: Date?
    private var timer: Timer?
    private var onStop: (() -> Void)?

    /// 展示 `show` 对应的屏幕捕获系统集成界面或系统位置。
    func show(selection: ScreenCaptureSelection, onStop: @escaping () -> Void) {
        hide()
        self.onStop = onStop
        startedAt = .now

        let controlState = RecordingControlState()
        self.controlState = controlState
        let hostingView = NSHostingView(
            rootView: RecordingControlView(state: controlState) { [weak self] in
                self?.stopRecording()
            }
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = LiquidGlassCornerGeometry.recordingControlRadius
        hostingView.layer?.masksToBounds = true

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
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel

        updateElapsedLabel()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsedLabel()
            }
        }
    }

    /// 取消或关闭 `hide` 对应的屏幕捕获系统集成流程，并清理临时状态。
    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        controlState = nil
        startedAt = nil
        onStop = nil
    }

    /// 应用 `updateElapsedLabel` 接收的新值，并更新相关屏幕捕获系统集成状态。
    private func updateElapsedLabel() {
        guard let startedAt else {
            return
        }
        let elapsedSeconds = Int(Date.now.timeIntervalSince(startedAt))
        controlState?.elapsedText = String(
            format: "%02d:%02d",
            elapsedSeconds / 60,
            elapsedSeconds % 60
        )
    }

    /// 结束 `stopRecording` 对应的屏幕捕获系统集成流程，并释放或重置相关资源。
    private func stopRecording() {
        let handler = onStop
        onStop = nil
        handler?()
    }
}

/// 使用共享 Liquid Glass 视觉语言展示录制状态、计时和停止操作。
private struct RecordingControlView: View {
    @ObservedObject var state: RecordingControlState
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(MacToolsGlassTheme.recording)
                .frame(width: 8, height: 8)
                .shadow(color: MacToolsGlassTheme.recording.opacity(0.45), radius: 4)

            Text("正在录制")
                .font(.system(size: 13, weight: .semibold))

            Text(state.elapsedText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(MacToolsGlassTheme.textSecondary)
                .monospacedDigit()

            Button(action: onStop) {
                Text("停止")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 44, height: 32)
            }
            .foregroundStyle(MacToolsGlassTheme.recording)
            .liquidGlassButtonStyle(
                cornerRadius: LiquidGlassCornerGeometry.smallControlRadius,
                minimumSize: CGSize(width: 44, height: 32)
            )
            .accessibilityLabel("停止录屏")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(
            width: ScreenCaptureOverlayLayout.recordingControlSize.width,
            height: ScreenCaptureOverlayLayout.recordingControlSize.height
        )
        .liquidGlassPanel(cornerRadius: LiquidGlassCornerGeometry.recordingControlRadius)
        .liquidGlassGroup(spacing: 6)
        .foregroundStyle(MacToolsGlassTheme.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在录制")
    }
}

/// 管理 `RecordingControlPanel` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
private final class RecordingControlPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
