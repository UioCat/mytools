import AVFoundation
import CoreMedia
import Foundation
import MacToolsCore
import ScreenCaptureKit

/// 一次会话的 writer 和输出队列始终属于同一 stream，不跨会话复用。
final class MP4RecordingResource: NSObject, ScreenRecordingResource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let source: ScreenCaptureSource
    private let destination: URL
    private let outputQueue = DispatchQueue(label: "com.mactools.screen-recording")
    private let outputQueueKey = DispatchSpecificKey<Void>()
    private let startCapture: @Sendable (SCStream) async throws -> Void
    private let stopCapture: @Sendable (SCStream) async throws -> Void
    private var stream: SCStream!
    // 以下可变状态仅由 outputQueue 访问。
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startedSession = false
    private var acceptsFrames = false
    private var streamFailure: Error?
    private var outputRegistered = false
    private var captureRequested = false
    private var ownsOutput = false

    init(
        source: ScreenCaptureSource,
        destination: URL,
        startCapture: @escaping @Sendable (SCStream) async throws -> Void = { try await $0.startCapture() },
        stopCapture: @escaping @Sendable (SCStream) async throws -> Void = { try await $0.stopCapture() }
    ) {
        self.source = source
        self.destination = destination
        self.startCapture = startCapture
        self.stopCapture = stopCapture
        super.init()
        outputQueue.setSpecific(key: outputQueueKey, value: ())
        stream = SCStream(filter: source.filter, configuration: source.configuration, delegate: self)
    }

    func start() async throws {
        try outputQueue.sync {
            let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
            self.writer = writer
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: source.configuration.width,
                AVVideoHeightKey: source.configuration.height
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw ScreenCaptureError.writerCreationFailed }
            writer.add(input)
            guard writer.startWriting() else { throw ScreenCaptureError.writerCreationFailed }
            ownsOutput = true
            self.input = input
            acceptsFrames = true
        }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        outputQueue.sync { outputRegistered = true; captureRequested = true }
        try await startCapture(stream)
    }

    func finish() async throws -> URL {
        let captureStopError = await stopStream()
        let state = outputQueue.sync { () -> (AVAssetWriter?, Error?) in
            acceptsFrames = false
            if writer?.status == .writing { input?.markAsFinished() }
            return (writer, streamFailure)
        }
        guard let writer = state.0 else { throw ScreenCaptureError.recorderNotRunning }
        if writer.status == .writing {
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
        }
        let success = ScreenRecordingCompletionPolicy.isSuccessful(
            writerCompleted: writer.status == .completed,
            hasRecordedFailure: state.1 != nil,
            hasCaptureStopError: captureStopError != nil)
        guard success else {
            removeOwnedOutput()
            throw writer.error ?? state.1 ?? captureStopError ?? ScreenCaptureError.writerFailed
        }
        return destination
    }

    func cancel() async {
        // ScreenCaptureKit 可以忽略 Task 取消；先等待停止，再解除输出引用和写入器。
        _ = await stopStream()
        outputQueue.sync {
            acceptsFrames = false
            if writer?.status == .writing { writer?.cancelWriting() }
        }
        removeOwnedOutput()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard self.stream === stream,
              type == .screen,
              sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer),
              let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first,
              let rawStatus = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              ScreenRecordingFramePolicy.shouldAppend(frameStatus: status,
                hasImageBuffer: CMSampleBufferGetImageBuffer(sampleBuffer) != nil) else { return }
        withOutputState {
            guard acceptsFrames, let writer, let input, input.isReadyForMoreMediaData else { return }
            if !startedSession {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                startedSession = true
            }
            if !input.append(sampleBuffer) { streamFailure = writer.error ?? ScreenCaptureError.writerFailed }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        withOutputState {
            guard self.stream === stream, acceptsFrames else { return }
            streamFailure = error
        }
    }

    private func stopStream() async -> Error? {
        let requested = outputQueue.sync { captureRequested }
        var stopError: Error?
        if requested {
            do { try await stopCapture(stream) } catch { stopError = error }
            // 保留失败标记，cancel 可在封口失败时再次尝试释放 stream。
            if stopError == nil { outputQueue.sync { captureRequested = false } }
        }
        if outputQueue.sync(execute: { outputRegistered }) {
            try? stream.removeStreamOutput(self, type: .screen)
            outputQueue.sync { outputRegistered = false }
        }
        return stopError
    }

    private func removeOwnedOutput() {
        outputQueue.sync {
            guard ownsOutput else { return }
            try? FileManager.default.removeItem(at: destination)
            ownsOutput = false
        }
    }

    private func withOutputState(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: outputQueueKey) != nil { operation() }
        else { outputQueue.sync(execute: operation) }
    }
}
