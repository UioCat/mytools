import AVFoundation
import CoreMedia
import Foundation
import MacToolsCore
import ScreenCaptureKit

protocol ScreenRecording: AnyObject, Sendable {
    var isRecording: Bool { get }
    func start(selection: ScreenCaptureSelection, destination: URL) async throws
    func stop() async throws -> URL
}

/// Mutable capture state is handed off through `outputQueue` and stopped before finalization.
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

    init(captureService: SystemScreenCaptureService) {
        self.captureService = captureService
        super.init()
        outputQueue.setSpecific(key: outputQueueKey, value: ())
    }

    var isRecording: Bool {
        stream != nil
    }

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

    private func resetState() {
        stream = nil
        writer = nil
        input = nil
        destination = nil
        startedSession = false
        streamFailure = nil
    }
}
