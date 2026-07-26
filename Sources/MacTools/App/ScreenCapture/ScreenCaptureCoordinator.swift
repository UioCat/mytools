// `ScreenCaptureCoordinator` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

import AppKit
import CoreGraphics
import Foundation
import MacToolsCore

/// 管理 `ScreenCaptureCoordinator` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
@MainActor
final class ScreenCaptureCoordinator {
    private let permissionService: PermissionService
    private let logger: Logger
    private let overlay = ScreenSelectionOverlayController()
    private let stillCapture: ScreenStillCapturing
    private let recorder: ScreenRecording
    private let settingsProvider: () -> ScreenCaptureSettings
    private let onSettingsChange: (ScreenCaptureSettings) -> Bool
    private let editor = ScreenshotEditorPanelController()
    private let recordingControl = RecordingControlPanelController()
    private let pasteboard: WritablePasteboard
    private var state: ScreenCaptureSessionState = .idle

    /// 创建 `ScreenCaptureCoordinator`，保存传入依赖并建立初始状态。
    init(
        permissionService: PermissionService,
        logger: Logger,
        captureService: SystemScreenCaptureService? = nil,
        stillCapture: ScreenStillCapturing? = nil,
        recorder: ScreenRecording? = nil,
        pasteboard: WritablePasteboard = SystemWritablePasteboard(),
        settingsProvider: @escaping () -> ScreenCaptureSettings = { .defaults },
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool = { _ in true }
    ) {
        let captureService = captureService ?? SystemScreenCaptureService()
        self.permissionService = permissionService
        self.logger = logger
        self.stillCapture = stillCapture ?? captureService
        self.recorder = recorder ?? MP4ScreenRecorder(captureService: captureService)
        self.pasteboard = pasteboard
        self.settingsProvider = settingsProvider
        self.onSettingsChange = onSettingsChange
    }

    /// 校验权限与会话互斥状态，同时预热共享内容并展示区域选择层。
    func start() {
        guard !isCaptureInProgress else {
            logger.info("screen capture request ignored while a session is active")
            return
        }

        guard permissionService.summary().canCaptureScreen || permissionService.requestScreenRecordingPermission() else {
            showScreenRecordingPermissionAlert()
            return
        }

        state.beginSelection()
        stillCapture.invalidatePreparation()
        Task { [weak self] in
            guard let self else {
                return
            }
            let startedAt = Date()
            do {
                try await stillCapture.prepare()
                let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                logger.info("screen capture source prepared in \(milliseconds) ms")
            } catch is CancellationError {
                return
            } catch {
                logger.error("screen capture source preparation failed: \(error)")
            }
        }
        overlay.present(
            onSelection: { [weak self] selection, mode in
                self?.beginCapture(selection: selection, mode: mode)
            },
            onCancel: { [weak self] in
                self?.state.cancel()
                self?.stillCapture.invalidatePreparation()
            }
        )
    }

    private var isCaptureInProgress: Bool {
        switch state {
        case .selecting, .selectionReady, .capturingScreenshot, .editingScreenshot, .recording:
            return true
        case .idle, .finished, .cancelled, .failed:
            return false
        }
    }

    /// 仅接受状态机认可的有效选择，再分派到截图或录屏流程。
    private func beginCapture(selection: ScreenCaptureSelection, mode: ScreenCaptureMode) {
        guard state.acceptSelection(selection) else {
            return
        }

        switch mode {
        case .screenshot:
            beginScreenshot(selection)
        case .recording:
            beginRecording(selection)
        }
    }

    /// 启动 `beginScreenshot` 对应的屏幕捕获系统集成流程，并建立所需资源。
    private func beginScreenshot(_ selection: ScreenCaptureSelection) {
        guard state.beginScreenshot() else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let startedAt = Date()
                let image = try await stillCapture.captureStill(for: selection)
                let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                logger.info("screen capture still image ready in \(milliseconds) ms")
                guard state.beginEditingScreenshot() else {
                    return
                }
                guard editor.present(
                    image: image,
                    selection: selection,
                    settings: settingsProvider(),
                    onSettingsChange: onSettingsChange,
                    onCopy: { [weak self] data in
                        self?.completeScreenshot(with: data)
                    },
                    onCancel: { [weak self] in
                        self?.state.cancel()
                        self?.stillCapture.invalidatePreparation()
                    }
                ) else {
                    throw ScreenCaptureError.editorPresentationFailed
                }
                logger.info("screen capture editor presented")
            } catch {
                fail(message: "截图失败，请检查屏幕录制权限后重试", error: error)
            }
        }
    }

    /// 把编辑后的 PNG 写入剪贴板，并结束截图会话和预热缓存。
    private func completeScreenshot(with data: Data) {
        do {
            try pasteboard.writeImageData(data)
            state.finish()
            stillCapture.invalidatePreparation()
            logger.info("annotated screenshot copied to pasteboard")
        } catch {
            fail(message: "截图复制失败，请重试", error: error)
        }
    }

    /// 启动 `beginRecording` 对应的屏幕捕获系统集成流程，并建立所需资源。
    private func beginRecording(_ selection: ScreenCaptureSelection) {
        guard state.beginRecording() else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let destination = try recordingDestination()
                try await recorder.start(selection: selection, destination: destination)
                stillCapture.invalidatePreparation()
                recordingControl.show(selection: selection, onStop: { [weak self] in
                    self?.stopRecording()
                })
                logger.info("screen recording started: \(destination.lastPathComponent)")
            } catch {
                fail(message: "录屏启动失败，请检查屏幕录制权限后重试", error: error)
            }
        }
    }

    /// 先关闭录制控制面板，再封口 MP4 并在 Finder 中定位成品。
    private func stopRecording() {
        recordingControl.hide()
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let destination = try await recorder.stop()
                state.finish()
                stillCapture.invalidatePreparation()
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                logger.info("screen recording saved: \(destination.path)")
            } catch {
                fail(message: "录屏保存失败，请重试", error: error)
            }
        }
    }

    /// 保存 `recordingDestination` 接收的屏幕捕获系统集成数据，并保持既有持久化约束。
    private func recordingDestination() throws -> URL {
        guard let downloadsDirectory = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw ScreenCaptureError.downloadsDirectoryUnavailable
        }
        return try RecordingDestinationResolver(directory: downloadsDirectory).nextURL()
    }

    /// 计算并返回 `fail` 对应的屏幕捕获系统集成数据或状态结果。
    private func fail(message: String, error: Error) {
        overlay.dismiss()
        editor.dismiss()
        recordingControl.hide()
        state.fail()
        stillCapture.invalidatePreparation()
        logger.error("screen capture failed: \(error)")
        let alert = NSAlert()
        alert.messageText = "屏幕采集失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 展示 `showScreenRecordingPermissionAlert` 对应的屏幕捕获系统集成界面或系统位置。
    private func showScreenRecordingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在系统设置中允许 MacTools 录制屏幕，然后重新使用截图与录屏快捷键。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            permissionService.openSystemSettings(for: .screenRecording)
        }
    }
}
