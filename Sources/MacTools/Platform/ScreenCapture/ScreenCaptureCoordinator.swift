// 截图与录屏平台能力的会话协调器。
// 负责权限、选区、截图编辑和录屏交接，纯状态转换由 MacToolsCore 定义。

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
    private var sessionGeneration = 0

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
        let captureService = captureService ?? SystemScreenCaptureService(logger: logger)
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

        sessionGeneration += 1
        let sessionGeneration = sessionGeneration
        state.beginSelection()
        Task { [weak self] in
            guard let self else {
                return
            }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            do {
                try await stillCapture.prepare()
                logger.info(
                    "screen capture source prepared in \(elapsedMilliseconds(since: startedAt)) ms"
                )
            } catch is CancellationError {
                return
            } catch {
                logger.error("screen capture source preparation failed: \(error)")
            }
        }
        overlay.present(
            onSelection: { [weak self] selection, mode in
                self?.beginCapture(
                    selection: selection,
                    mode: mode,
                    submittedAt: DispatchTime.now().uptimeNanoseconds,
                    sessionGeneration: sessionGeneration
                )
            },
            onCancel: { [weak self] in
                self?.cancelSession(sessionGeneration: sessionGeneration)
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

    private var isCancelled: Bool {
        if case .cancelled = state {
            return true
        }
        return false
    }

    /// 仅接受状态机认可的有效选择，再分派到截图或录屏流程。
    private func beginCapture(
        selection: ScreenCaptureSelection,
        mode: ScreenCaptureMode,
        submittedAt: UInt64,
        sessionGeneration: Int
    ) {
        guard self.sessionGeneration == sessionGeneration else {
            return
        }
        guard state.acceptSelection(selection) else {
            return
        }

        switch mode {
        case .screenshot:
            beginScreenshot(
                selection,
                submittedAt: submittedAt,
                sessionGeneration: sessionGeneration
            )
        case .recording:
            beginRecording(selection, sessionGeneration: sessionGeneration)
        }
    }

    /// 启动 `beginScreenshot` 对应的屏幕捕获系统集成流程，并建立所需资源。
    private func beginScreenshot(
        _ selection: ScreenCaptureSelection,
        submittedAt: UInt64,
        sessionGeneration: Int
    ) {
        guard state.beginScreenshot() else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let startedAt = DispatchTime.now().uptimeNanoseconds
                let image = try await stillCapture.captureStill(for: selection)
                guard self.sessionGeneration == sessionGeneration, !isCancelled else {
                    return
                }
                logger.info(
                    "screen capture still image ready in \(elapsedMilliseconds(since: startedAt)) ms; "
                        + "total \(elapsedMilliseconds(since: submittedAt)) ms"
                )
                guard state.beginEditingScreenshot() else {
                    return
                }

                let editorPreparationStartedAt = DispatchTime.now().uptimeNanoseconds
                editor.prepare(
                    image: image,
                    selection: selection,
                    settings: settingsProvider(),
                    onSettingsChange: onSettingsChange,
                    onCopy: { [weak self] data in
                        self?.completeScreenshot(with: data)
                    },
                    onCancel: { [weak self] in
                        self?.cancelCurrentSession()
                    }
                )
                logger.info(
                    "screen capture editor prepared in "
                        + "\(elapsedMilliseconds(since: editorPreparationStartedAt)) ms"
                )

                let handoffStartedAt = DispatchTime.now().uptimeNanoseconds
                guard let editorView = editor.preparedContentView(),
                      overlay.presentEditor(
                          editorView,
                          for: selection,
                          escapeHandler: { [weak editor] hasMarkedText in
                              editor?.handleEscape(hasMarkedText: hasMarkedText) ?? .cancelSession
                          }
                      ) else {
                    throw ScreenCaptureError.editorPresentationFailed
                }
                logger.info(
                    "screen capture editor presented in "
                        + "\(elapsedMilliseconds(since: handoffStartedAt)) ms; "
                        + "total \(elapsedMilliseconds(since: submittedAt)) ms"
                )
            } catch {
                guard self.sessionGeneration == sessionGeneration, !isCancelled else {
                    return
                }
                fail(message: "截图失败，请检查屏幕录制权限后重试", error: error)
            }
        }
    }

    /// 把编辑后的 PNG 写入剪贴板并结束截图会话，保留短期预热缓存。
    private func completeScreenshot(with data: Data) {
        overlay.dismiss()
        editor.dismiss()
        do {
            try pasteboard.writeImageData(data)
            state.finish()
            logger.info("annotated screenshot copied to pasteboard")
        } catch {
            fail(message: "截图复制失败，请重试", error: error)
        }
    }

    /// 启动 `beginRecording` 对应的屏幕捕获系统集成流程，并建立所需资源。
    private func beginRecording(_ selection: ScreenCaptureSelection, sessionGeneration: Int) {
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
                guard self.sessionGeneration == sessionGeneration, !isCancelled else {
                    _ = try? await recorder.stop()
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                overlay.dismiss()
                recordingControl.show(selection: selection, onStop: { [weak self] in
                    self?.stopRecording()
                })
                logger.info("screen recording started: \(destination.lastPathComponent)")
            } catch {
                guard self.sessionGeneration == sessionGeneration, !isCancelled else {
                    return
                }
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
        sessionGeneration += 1
        stillCapture.invalidatePreparation()
        logger.error("screen capture failed: \(error)")
        let alert = NSAlert()
        alert.messageText = "屏幕采集失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 取消匹配的选区会话，并使该会话尚未返回的异步结果永久失效。
    private func cancelSession(sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration else {
            return
        }
        cancelCurrentSession()
    }

    /// 取消当前会话但保留短期共享内容缓存，便于快速重新截图。
    private func cancelCurrentSession() {
        overlay.dismiss()
        editor.dismiss()
        state.cancel()
        sessionGeneration += 1
    }

    /// 使用单调时钟计算阶段耗时，避免系统时间调整影响性能日志。
    private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        return Int(elapsedNanoseconds / 1_000_000)
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
