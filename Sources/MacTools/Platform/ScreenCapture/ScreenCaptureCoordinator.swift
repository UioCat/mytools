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
    private let overlay: ScreenSelectionPresenting
    private let stillCapture: ScreenStillCapturing
    private let recorder: ScreenRecording
    private let settingsProvider: () -> ScreenCaptureSettings
    private let onSettingsChange: (ScreenCaptureSettings) -> Bool
    private let editor: ScreenshotEditing
    private let recordingControl: RecordingControlPresenting
    private let displaySelections: () -> [ScreenCaptureSelection]
    private let destinationProvider: (() throws -> URL)?
    private let revealRecording: (URL) -> Void
    private let failurePresenter: ((String) -> Void)?
    private let discardRecording: @Sendable (URL) async -> Void
    private let pasteboard: WritablePasteboard
    private var state: ScreenCaptureSessionState = .idle
    private var sessionGeneration = 0
    private var snapshots: [ScreenCaptureSnapshot] = []
    private var preparationTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var recordingStopTask: Task<Void, Never>?

    /// 创建 `ScreenCaptureCoordinator`，保存传入依赖并建立初始状态。
    init(
        permissionService: PermissionService,
        logger: Logger,
        captureService: SystemScreenCaptureService? = nil,
        stillCapture: ScreenStillCapturing? = nil,
        recorder: ScreenRecording? = nil,
        pasteboard: WritablePasteboard = SystemWritablePasteboard(),
        settingsProvider: @escaping () -> ScreenCaptureSettings = { .defaults },
        onSettingsChange: @escaping (ScreenCaptureSettings) -> Bool = { _ in true },
        overlay: ScreenSelectionPresenting? = nil,
        editor: ScreenshotEditing? = nil,
        recordingControl: RecordingControlPresenting? = nil,
        displaySelections: (() -> [ScreenCaptureSelection])? = nil,
        destinationProvider: (() throws -> URL)? = nil,
        revealRecording: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
        failurePresenter: ((String) -> Void)? = nil,
        discardRecording: @escaping @Sendable (URL) async -> Void = { destination in
            await Task.detached { try? FileManager.default.removeItem(at: destination) }.value
        }
    ) {
        let captureService = captureService ?? SystemScreenCaptureService(logger: logger)
        self.permissionService = permissionService
        self.logger = logger
        self.stillCapture = stillCapture ?? captureService
        self.recorder = recorder ?? MP4ScreenRecorder(captureService: captureService)
        self.pasteboard = pasteboard
        self.settingsProvider = settingsProvider
        self.onSettingsChange = onSettingsChange
        self.overlay = overlay ?? ScreenSelectionOverlayController()
        self.editor = editor ?? ScreenshotEditorPanelController()
        self.recordingControl = recordingControl ?? RecordingControlPanelController()
        self.displaySelections = displaySelections ?? Self.currentDisplaySelections
        self.destinationProvider = destinationProvider
        self.revealRecording = revealRecording
        self.failurePresenter = failurePresenter
        self.discardRecording = discardRecording
    }

    /// 校验权限与会话互斥状态，先冻结屏幕再展示区域选择层。
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
        let displays = displaySelections()
        overlay.prepareForCapture { [weak self] in
            self?.cancelSession(sessionGeneration: sessionGeneration)
        }
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 在任何选区窗口出现或接收鼠标事件之前保存临时弹窗。
                // 每次会话重新采集像素，不能复用共享内容预热缓存中的旧画面。
                stillCapture.invalidatePreparation()
                var captured: [ScreenCaptureSnapshot] = []
                for display in displays {
                    let image = try await stillCapture.captureStill(for: display)
                    try Task.checkCancellation()
                    captured.append(ScreenCaptureSnapshot(
                        displayID: display.displayID, displayFrame: display.displayFrame, image: image
                    ))
                }
                guard self.sessionGeneration == sessionGeneration, !isCancelled else { return }
                guard !captured.isEmpty else { throw ScreenCaptureError.displayUnavailable }
                snapshots = captured
                preparationTask = nil
                overlay.present(
                    snapshots: captured,
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
            } catch {
                guard self.sessionGeneration == sessionGeneration, !isCancelled else { return }
                fail(message: "截图准备失败，请检查屏幕录制权限后重试", error: error)
            }
        }
    }

    private var isCaptureInProgress: Bool {
        // Escape 使界面代际失效，但底层启动或封口完成前仍拥有录屏资源。
        if recordingTask != nil || recordingStopTask != nil {
            return true
        }
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
                guard let image = snapshots.first(where: { $0.displayID == selection.displayID })?
                    .croppedImage(for: selection) else {
                    throw ScreenCaptureError.displayUnavailable
                }
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
                        self?.completeScreenshot(with: data, sessionGeneration: sessionGeneration)
                    },
                    onCancel: { [weak self] in
                        self?.cancelSession(sessionGeneration: sessionGeneration)
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
    private func completeScreenshot(with data: Data, sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              case .editingScreenshot = state else {
            return
        }
        state.finish()
        overlay.dismiss()
        snapshots.removeAll()
        preparationTask?.cancel()
        preparationTask = nil
        editor.dismiss()
        do {
            try pasteboard.writeImageData(data)
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

        recordingTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { recordingTask = nil }
            do {
                try Task.checkCancellation()
                let destination = try recordingDestination()
                try await recorder.start(selection: selection, destination: destination)
                guard self.sessionGeneration == sessionGeneration, !isCancelled, !Task.isCancelled else {
                    _ = try? await recorder.stop()
                    await discardRecording(destination)
                    return
                }
                overlay.dismiss()
                snapshots.removeAll()
                recordingControl.show(selection: selection, onStop: { [weak self] in
                    self?.stopRecording(sessionGeneration: sessionGeneration)
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
    private func stopRecording(sessionGeneration: Int) {
        guard self.sessionGeneration == sessionGeneration,
              case .recording = state,
              recordingStopTask == nil else {
            return
        }
        recordingControl.hide()
        recordingStopTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer { recordingStopTask = nil }
            do {
                let destination = try await recorder.stop()
                guard self.sessionGeneration == sessionGeneration, !isCancelled else { return }
                state.finish()
                revealRecording(destination)
                logger.info("screen recording saved: \(destination.path)")
            } catch {
                guard self.sessionGeneration == sessionGeneration, !isCancelled else { return }
                fail(message: "录屏保存失败，请重试", error: error)
            }
        }
    }

    /// 保存 `recordingDestination` 接收的屏幕捕获系统集成数据，并保持既有持久化约束。
    private func recordingDestination() throws -> URL {
        if let destinationProvider {
            return try destinationProvider()
        }
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
        snapshots.removeAll()
        preparationTask?.cancel()
        preparationTask = nil
        editor.dismiss()
        recordingControl.hide()
        state.fail()
        sessionGeneration += 1
        stillCapture.invalidatePreparation()
        logger.error("screen capture failed: \(error)")
        if let failurePresenter {
            failurePresenter(message)
            return
        }
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
        snapshots.removeAll()
        preparationTask?.cancel()
        preparationTask = nil
        editor.dismiss()
        state.cancel()
        sessionGeneration += 1
        recordingTask?.cancel()
    }

    /// 使用单调时钟计算阶段耗时，避免系统时间调整影响性能日志。
    private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        return Int(elapsedNanoseconds / 1_000_000)
    }

    private static func currentDisplaySelections() -> [ScreenCaptureSelection] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return ScreenCaptureSelection(
                displayID: id.uint32Value, displayFrame: screen.frame, rawSelectionFrame: screen.frame
            )
        }
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
