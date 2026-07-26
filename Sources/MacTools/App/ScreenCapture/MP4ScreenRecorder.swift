// `MP4ScreenRecorder` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

import AVFoundation
import CoreMedia
import Foundation
import MacToolsCore
import ScreenCaptureKit

/// 定义 `ScreenRecording` 在屏幕捕获系统集成中需要满足的能力边界。
protocol ScreenRecording: AnyObject, Sendable {
    var isRecording: Bool { get }
    /// 建立只含 H.264 视频轨道的 MP4 写入器，并把 ScreenCaptureKit 帧交给串行输出队列。
    func start(selection: ScreenCaptureSelection, destination: URL) async throws
    /// 停止采集、封口视频轨道并检查采集与写入错误；失败时删除不完整文件。
    func stop() async throws -> URL
}

/// 可变采集状态只通过 `outputQueue` 交接，并在文件收尾前停止写入。
final class MP4ScreenRecorder: NSObject, ScreenRecording, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let captureService: SystemScreenCaptureService
    private let outputQueue = DispatchQueue(label: "com.mactools.screen-recording")
    private let outputQueueKey = DispatchSpecificKey<Void>()
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var destination: URL?
    private var startedSession = false
    private var streamFailure: Error?

    /// 创建 `MP4ScreenRecorder`，保存传入依赖并建立初始状态。
    init(captureService: SystemScreenCaptureService) {
        self.captureService = captureService
        super.init()
        outputQueue.setSpecific(key: outputQueueKey, value: ())
    }

    var isRecording: Bool {
        stream != nil
    }

    /// 异步启动 `start` 对应的屏幕捕获系统集成流程，并建立所需资源。
    func start(selection: ScreenCaptureSelection, destination: URL) async throws {
        guard !isRecording else {
            throw ScreenCaptureError.captureAlreadyRunning
        }

        let source = try await captureService.source(for: selection, purpose: .recording)
        source.configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)

        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: source.configuration.width,
                AVVideoHeightKey: source.configuration.height
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw ScreenCaptureError.writerCreationFailed
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw ScreenCaptureError.writerCreationFailed
        }

        let stream = SCStream(filter: source.filter, configuration: source.configuration, delegate: self)
        self.stream = stream
        self.writer = writer
        self.input = input
        self.destination = destination
        self.startedSession = false
        self.streamFailure = nil

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            resetState()
            throw error
        }
    }

    /// 异步结束 `stop` 对应的屏幕捕获系统集成流程，并释放或重置相关资源。
    func stop() async throws -> URL {
        guard let stream, let writer, let input, let destination else {
            throw ScreenCaptureError.recorderNotRunning
        }

        var captureStopError: Error?
        do {
            try await stream.stopCapture()
        } catch {
            captureStopError = error
        }

        let recordedStreamFailure = outputQueue.sync { () -> Error? in
            if writer.status == .writing {
                input.markAsFinished()
            }
            return streamFailure
        }

        if writer.status == .writing {
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }

        let writingError = writer.error ?? recordedStreamFailure ?? captureStopError
        let completedSuccessfully = ScreenRecordingCompletionPolicy.isSuccessful(
            writerCompleted: writer.status == .completed,
            hasRecordedFailure: recordedStreamFailure != nil,
            hasCaptureStopError: captureStopError != nil
        )
        resetState()

        guard completedSuccessfully else {
            try? FileManager.default.removeItem(at: destination)
            throw writingError ?? ScreenCaptureError.writerFailed
        }

        return destination
    }

    /// 记录系统主动终止采集的错误，留待显式 `stop()` 时统一完成写入与清理。
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                  sampleBuffer,
                  createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let frameStatusRawValue = attachments[.status] as? Int,
              let frameStatus = SCFrameStatus(rawValue: frameStatusRawValue),
              ScreenRecordingFramePolicy.shouldAppend(
                  frameStatus: frameStatus,
                  hasImageBuffer: CMSampleBufferGetImageBuffer(sampleBuffer) != nil
              ),
              let writer,
              let input,
              input.isReadyForMoreMediaData else {
            return
        }

        if !startedSession {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            startedSession = true
        }
        guard input.append(sampleBuffer) else {
            streamFailure = writer.error ?? ScreenCaptureError.writerFailed
            return
        }
    }

    /// 响应 `stream` 对应的系统或界面回调，并同步当前交互状态。
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let recordFailure = { [weak self] in
            guard let self, self.stream === stream else {
                return
            }
            self.streamFailure = error
        }

        if DispatchQueue.getSpecific(key: outputQueueKey) != nil {
            recordFailure()
        } else {
            outputQueue.sync(execute: recordFailure)
        }
    }

    /// 调整 `resetState` 涉及的屏幕捕获系统集成状态，并保持迁移或恢复语义。
    private func resetState() {
        stream = nil
        writer = nil
        input = nil
        destination = nil
        startedSession = false
        streamFailure = nil
    }
}
