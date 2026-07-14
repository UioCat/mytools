import AVFoundation
import CoreMedia
import Foundation
import MacToolsCore
import ScreenCaptureKit

protocol ScreenRecording: AnyObject {
    var isRecording: Bool { get }
    func start(selection: ScreenCaptureSelection, destination: URL) async throws
    func stop() async throws -> URL
}

final class MP4ScreenRecorder: NSObject, ScreenRecording, SCStreamOutput, SCStreamDelegate {
    private let captureService: SystemScreenCaptureService
    private let outputQueue = DispatchQueue(label: "com.mactools.screen-recording")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var destination: URL?
    private var startedSession = false

    init(captureService: SystemScreenCaptureService) {
        self.captureService = captureService
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
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        self.stream = stream
        self.writer = writer
        self.input = input
        self.destination = destination
        self.startedSession = false
    }

    func stop() async throws -> URL {
        guard let stream, let writer, let input, let destination else {
            throw ScreenCaptureError.recorderNotRunning
        }

        try await stream.stopCapture()
        outputQueue.sync {
            input.markAsFinished()
        }
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        self.stream = nil
        self.writer = nil
        self.input = nil
        self.destination = nil
        self.startedSession = false

        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw ScreenCaptureError.writerFailed
        }

        return destination
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let writer,
              let input,
              input.isReadyForMoreMediaData else {
            return
        }

        if !startedSession {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            startedSession = true
        }
        input.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        guard self.stream === stream else {
            return
        }

        self.stream = nil
    }
}
