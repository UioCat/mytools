import AppKit
import CoreGraphics
import Foundation
import MacToolsCore

@MainActor
final class ScreenCaptureCoordinator {
    private let permissionService: PermissionService
    private let logger: Logger
    private let overlay = ScreenSelectionOverlayController()
    private let stillCapture: ScreenStillCapturing
    private let recorder: ScreenRecording
    private let editor = ScreenshotEditorPanelController()
    private let recordingControl = RecordingControlPanelController()
    private let pasteboard: WritablePasteboard
    private var state: ScreenCaptureSessionState = .idle

    init(
        permissionService: PermissionService,
        logger: Logger,
        stillCapture: ScreenStillCapturing = SystemScreenCaptureService(),
        recorder: ScreenRecording = MP4ScreenRecorder(),
        pasteboard: WritablePasteboard = SystemWritablePasteboard()
    ) {
        self.permissionService = permissionService
        self.logger = logger
        self.stillCapture = stillCapture
        self.recorder = recorder
        self.pasteboard = pasteboard
    }

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
        overlay.present(
            onMode: { [weak self] selection, mode in
                self?.beginCapture(selection: selection, mode: mode)
            },
            onCancel: { [weak self] in
                self?.state.cancel()
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

    private func beginScreenshot(_ selection: ScreenCaptureSelection) {
        guard state.beginScreenshot() else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let image = try await stillCapture.captureStill(for: selection)
                guard state.beginEditingScreenshot() else {
                    return
                }
                editor.present(
                    image: image,
                    onCopy: { [weak self] data in
                        self?.completeScreenshot(with: data)
                    },
                    onCancel: { [weak self] in
                        self?.state.cancel()
                    }
                )
            } catch {
                fail(message: "截图失败，请检查屏幕录制权限后重试", error: error)
            }
        }
    }

    private func completeScreenshot(with data: Data) {
        do {
            try pasteboard.writeImageData(data)
            state.finish()
            logger.info("annotated screenshot copied to pasteboard")
        } catch {
            fail(message: "截图复制失败，请重试", error: error)
        }
    }

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
                recordingControl.show(selection: selection, onStop: { [weak self] in
                    self?.stopRecording()
                })
                logger.info("screen recording started: \(destination.lastPathComponent)")
            } catch {
                fail(message: "录屏启动失败，请检查屏幕录制权限后重试", error: error)
            }
        }
    }

    private func stopRecording() {
        recordingControl.hide()
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let destination = try await recorder.stop()
                state.finish()
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                logger.info("screen recording saved: \(destination.path)")
            } catch {
                fail(message: "录屏保存失败，请重试", error: error)
            }
        }
    }

    private func recordingDestination() throws -> URL {
        guard let downloadsDirectory = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw ScreenCaptureError.downloadsDirectoryUnavailable
        }
        return try RecordingDestinationResolver(directory: downloadsDirectory).nextURL()
    }

    private func fail(message: String, error: Error) {
        overlay.dismiss()
        editor.dismiss()
        recordingControl.hide()
        state.fail()
        logger.error("screen capture failed: \(error)")
        let alert = NSAlert()
        alert.messageText = "屏幕采集失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

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
