// 每次录屏拥有独立的采集和写入资源；协调器只接触启动与停止边界。

import CoreMedia
import Foundation
import MacToolsCore

@MainActor
protocol ScreenRecording: AnyObject {
    var isRecording: Bool { get }
    func start(selection: ScreenCaptureSelection, destination: URL) async throws
    func stop() async throws -> URL
}

/// 资源适配器负责串行帧写入和封口，不拥有用户界面会话。
protocol ScreenRecordingResource: AnyObject, Sendable {
    func start() async throws
    func finish() async throws -> URL
    func cancel() async
}

@MainActor
final class MP4ScreenRecorder: ScreenRecording {
    private enum Phase { case starting, recording, stopping }

    @MainActor
    private final class Session {
        var phase: Phase = .starting
        var resource: (any ScreenRecordingResource)?
        var startTask: Task<Void, Error>?
        var finishTask: Task<URL, Error>?
    }

    private let makeResource: @Sendable (ScreenCaptureSelection, URL) async throws -> any ScreenRecordingResource
    private var session: Session?

    convenience init(captureService: SystemScreenCaptureService) {
        self.init { selection, destination in
            let source = try await captureService.source(for: selection, purpose: .recording)
            source.configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            return MP4RecordingResource(source: source, destination: destination)
        }
    }

    init(makeResource: @escaping @Sendable (ScreenCaptureSelection, URL) async throws -> any ScreenRecordingResource) {
        self.makeResource = makeResource
    }

    // 来源查询、启动、写入及清理都占用同一会话，不能在 await 期间插入新启动。
    var isRecording: Bool { session != nil }

    func start(selection: ScreenCaptureSelection, destination: URL) async throws {
        guard session == nil else { throw ScreenCaptureError.captureAlreadyRunning }
        let session = Session()
        self.session = session
        let startTask = Task {
            try Task.checkCancellation()
            let resource = try await makeResource(selection, destination)
            session.resource = resource
            try Task.checkCancellation()
            try await resource.start()
            try Task.checkCancellation()
        }
        session.startTask = startTask
        do {
            try await withTaskCancellationHandler {
                try await startTask.value
                try Task.checkCancellation()
            } onCancel: {
                startTask.cancel()
            }
            guard self.session === session, session.phase == .starting else { throw CancellationError() }
            session.phase = .recording
        } catch {
            if self.session === session {
                _ = await finishTask(for: session, cancelStart: true).result
            }
            throw error
        }
    }

    func stop() async throws -> URL {
        guard let session else { throw ScreenCaptureError.recorderNotRunning }
        return try await finishTask(for: session, cancelStart: session.phase == .starting).value
    }

    private func finishTask(for session: Session, cancelStart: Bool) -> Task<URL, Error> {
        if let finishTask = session.finishTask { return finishTask }
        session.phase = .stopping
        if cancelStart { session.startTask?.cancel() }
        let finishTask = Task { [self] in
            defer {
                // 只有该会话自己的收尾可以释放互斥；旧等待者不能清除下一次会话。
                if self.session === session { self.session = nil }
                session.startTask = nil
                session.finishTask = nil
            }
            if cancelStart {
                _ = await session.startTask?.result
                await session.resource?.cancel()
                throw CancellationError()
            }
            guard let resource = session.resource else { throw ScreenCaptureError.recorderNotRunning }
            do {
                return try await resource.finish()
            } catch {
                await resource.cancel()
                throw error
            }
        }
        session.finishTask = finishTask
        return finishTask
    }
}
