import AppKit
import AVFoundation
import MacToolsCore
import ScreenCaptureKit
import XCTest
@testable import MacTools

final class MP4ScreenRecorderTests: XCTestCase {
    private let selection = ScreenCaptureSelection(displayID: 7, displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                                   rawSelectionFrame: CGRect(x: 0, y: 0, width: 50, height: 50))

    @MainActor
    func testStartingReservesResourcesBeforeSourceReturns() async throws {
        let first = RecordingResourceDouble()
        let second = RecordingResourceDouble()
        let factory = RecordingFactory(first: first, second: second)
        await factory.pauseFirstSource()
        let recorder = MP4ScreenRecorder(makeResource: { _, _ in try await factory.make() })
        let startA = Task { try await recorder.start(selection: selection, destination: first.destination) }
        await waitUntil { await factory.isWaiting }
        XCTAssertTrue(recorder.isRecording, "The source lookup is already part of the active recording session")
        let startB = await Task { try await recorder.start(selection: selection, destination: second.destination) }.result
        assertError(startB, equals: .captureAlreadyRunning)
        await factory.releaseSource()
        try await startA.value
        let secondStarted = await second.startCount
        XCTAssertEqual(secondStarted, 0, "A rejected start cannot create a second writer/stream")
        _ = try await recorder.stop()
        await second.cancel()
    }

    @MainActor
    func testStopDuringSourceLookupWaitsForCancellationCleanup() async throws {
        let resource = RecordingResourceDouble()
        let factory = RecordingFactory(first: resource, second: RecordingResourceDouble())
        await factory.pauseFirstSource()
        let recorder = MP4ScreenRecorder(makeResource: { _, _ in try await factory.make() })
        let start = Task { try await recorder.start(selection: selection, destination: resource.destination) }
        await waitUntil { await factory.isWaiting }
        let stop = Task { try await recorder.stop() }
        await drainTasks()
        XCTAssertTrue(recorder.isRecording)
        await factory.releaseSource()
        let startResult = await start.result
        let stopResult = await stop.result
        XCTAssertTrue(isCancelled(startResult))
        XCTAssertTrue(isCancelled(stopResult))
        let cancelled = await resource.cancelCount
        let started = await resource.startCount
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(started, 0)
        XCTAssertFalse(recorder.isRecording)
    }

    @MainActor
    func testTaskCancellationAfterNonCooperativeStartWaitsForCleanup() async throws {
        let resource = RecordingResourceDouble()
        await resource.pauseStart()
        await resource.pauseCancel()
        let recorder = MP4ScreenRecorder(makeResource: { _, _ in resource })
        let start = Task { try await recorder.start(selection: selection, destination: resource.destination) }
        await waitUntil { await resource.isStartWaiting }
        start.cancel()
        await resource.releaseStart()
        await waitUntil { await resource.isCancelWaiting }
        XCTAssertTrue(recorder.isRecording, "Cancelled start still owns resources while cleanup is pending")
        let secondStart = await Task { try await recorder.start(selection: selection, destination: resource.destination) }.result
        assertError(secondStart, equals: .captureAlreadyRunning)
        await resource.releaseCancel()
        let result = await start.result
        XCTAssertTrue(isCancelled(result))
        let cancelled = await resource.cancelCount
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(recorder.isRecording)
    }

    @MainActor
    func testConcurrentStopsShareFinalizationAndCannotClearNextSession() async throws {
        let first = RecordingResourceDouble()
        let second = RecordingResourceDouble()
        await first.pauseFinish()
        let factory = RecordingFactory(first: first, second: second)
        let recorder = MP4ScreenRecorder(makeResource: { _, _ in try await factory.make() })
        try await recorder.start(selection: selection, destination: first.destination)
        let stopA = Task { try await recorder.stop() }
        await waitUntil { await first.isFinishWaiting }
        let stopB = Task { try await recorder.stop() }
        await drainTasks()
        let finishes = await first.finishCount
        XCTAssertEqual(finishes, 1)
        let blockedStart = await Task { try await recorder.start(selection: selection, destination: second.destination) }.result
        assertError(blockedStart, equals: .captureAlreadyRunning)
        await first.releaseFinish()
        _ = try await stopA.value
        _ = try await stopB.value
        try await recorder.start(selection: selection, destination: second.destination)
        XCTAssertTrue(recorder.isRecording)
        _ = try await recorder.stop()
    }

    @MainActor
    func testFailedStartDeletesOnlyItsDestinationAfterCleanup() async throws {
        let first = RecordingResourceDouble()
        await first.failStart()
        await first.pauseCancel()
        let second = RecordingResourceDouble()
        let factory = RecordingFactory(first: first, second: second)
        let deletion = RecordingDeletionProbe()
        await first.setCleanup { await deletion.record($0) }
        let recorder = MP4ScreenRecorder(makeResource: { _, _ in try await factory.make() })
        let start = Task { try await recorder.start(selection: selection, destination: first.destination) }
        await waitUntil { await first.isCancelWaiting }
        let blocked = await Task { try await recorder.start(selection: selection, destination: second.destination) }.result
        assertError(blocked, equals: .captureAlreadyRunning)
        let deletedBeforeCleanup = await deletion.destinations
        XCTAssertTrue(deletedBeforeCleanup.isEmpty)
        await first.releaseCancel()
        assertError(await start.result, equals: .writerFailed)
        let deleted = await deletion.destinations
        XCTAssertEqual(deleted, [first.destination])
        try await recorder.start(selection: selection, destination: second.destination)
        _ = try await recorder.stop()
        let deletedAfterRestart = await deletion.destinations
        XCTAssertEqual(deletedAfterRestart, [first.destination])
    }

    @MainActor
    func testFailedFinishCleansItsOwnDestinationBeforeReleasingResources() async throws {
        let resource = RecordingResourceDouble()
        await resource.failFinish()
        await resource.pauseCancel()
        let deletion = RecordingDeletionProbe()
        await resource.setCleanup { await deletion.record($0) }
        let recorder = MP4ScreenRecorder(makeResource: { _, _ in resource })
        try await recorder.start(selection: selection, destination: resource.destination)
        let stop = Task { try await recorder.stop() }
        await waitUntil { await resource.isCancelWaiting }
        XCTAssertTrue(recorder.isRecording, "Failed finalization still owns resources until cancellation finishes")
        await resource.releaseCancel()
        assertError(await stop.result, equals: .writerFailed)
        let deleted = await deletion.destinations
        XCTAssertEqual(deleted, [resource.destination])
        XCTAssertFalse(recorder.isRecording)
    }

    func testFailedWriterCreationCannotDeleteAnExistingDestination() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        let existing = Data([0x41, 0x42, 0x43])
        try existing.write(to: destination)
        defer { try? FileManager.default.removeItem(at: destination) }
        let configuration = SCStreamConfiguration()
        configuration.width = 32
        configuration.height = 32
        let resource = MP4RecordingResource(
            source: ScreenCaptureSource(filter: SCContentFilter(), configuration: configuration),
            destination: destination, startCapture: { _ in }, stopCapture: { _ in })
        do {
            try await resource.start()
            XCTFail("An existing destination cannot be used for a new writer")
        } catch {
            await resource.cancel()
        }
        XCTAssertEqual(try Data(contentsOf: destination), existing, "Cleanup can delete only output created by this session")
    }

    func testFailedCaptureStartRemovesOnlyTheWriterOwnedOutput() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let configuration = SCStreamConfiguration()
        configuration.width = 32
        configuration.height = 32
        let resource = MP4RecordingResource(
            source: ScreenCaptureSource(filter: SCContentFilter(), configuration: configuration),
            destination: destination,
            startCapture: { _ in throw ScreenCaptureError.writerFailed }, stopCapture: { _ in })
        do {
            try await resource.start()
            XCTFail("The injected capture failure must propagate")
        } catch {
            XCTAssertEqual(error as? ScreenCaptureError, .writerFailed)
            await resource.cancel()
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testFramesFromAnotherStreamCannotEnterCurrentMP4() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        let configuration = SCStreamConfiguration()
        configuration.width = 32
        configuration.height = 32
        let source = ScreenCaptureSource(filter: SCContentFilter(), configuration: configuration)
        let probe = RecordingStreamProbe()
        let resource = MP4RecordingResource(source: source, destination: destination,
                                             startCapture: { await probe.record($0) }, stopCapture: { _ in })
        try await resource.start()
        let capturedStream = await probe.stream
        let currentStream = try XCTUnwrap(capturedStream)
        let otherStream = SCStream(filter: SCContentFilter(), configuration: configuration, delegate: nil)
        resource.stream(otherStream, didOutputSampleBuffer: try makeFrame(time: 0, red: true), of: .screen)
        resource.stream(currentStream, didOutputSampleBuffer: try makeFrame(time: 1), of: .screen)
        _ = try await resource.finish()
        let asset = AVURLAsset(url: destination)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            count += 1
            let pixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample))
            CVPixelBufferLockBaseAddress(pixels, .readOnly)
            let address = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
            XCTAssertLessThan(address.load(fromByteOffset: 2, as: UInt8.self), 16,
                              "The foreign stream's generated red pixels cannot enter this MP4")
            CVPixelBufferUnlockBaseAddress(pixels, .readOnly)
        }
        XCTAssertEqual(count, 1, "Only the current stream's generated frame belongs in this file")
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Expected recording boundary was not reached", file: file, line: line)
    }

    @MainActor
    private func drainTasks() async { for _ in 0..<100 { await Task.yield() } }

    private func assertError<T>(_ result: Result<T, Error>, equals expected: ScreenCaptureError,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard case let .failure(error) = result else { XCTFail("Expected \(expected)", file: file, line: line); return }
        XCTAssertEqual(error as? ScreenCaptureError, expected, file: file, line: line)
    }

    private func isCancelled<T>(_ result: Result<T, Error>) -> Bool {
        if case let .failure(error) = result { return error is CancellationError }
        return false
    }

    private func makeFrame(time: Int64, red: Bool = false) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &pixelBuffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let address = CVPixelBufferGetBaseAddress(pixels) {
            memset(address, 0, CVPixelBufferGetDataSize(pixels))
            for y in 0..<32 {
                for x in 0..<32 {
                    let offset = y * CVPixelBufferGetBytesPerRow(pixels) + x * 4
                    address.storeBytes(of: red ? UInt8(255) : UInt8(0), toByteOffset: offset + 2, as: UInt8.self)
                    address.storeBytes(of: UInt8(255), toByteOffset: offset + 3, as: UInt8.self)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var description: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixels,
                                                                    formatDescriptionOut: &description), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMTime(value: time, timescale: 30), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixels,
            formatDescription: try XCTUnwrap(description), sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        let result = try XCTUnwrap(sample)
        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(result, createIfNecessary: true) as? [NSMutableDictionary])
        attachments[0][SCStreamFrameInfo.status.rawValue] = SCFrameStatus.complete.rawValue
        return result
    }
}

private actor RecordingFactory {
    let first: RecordingResourceDouble
    let second: RecordingResourceDouble
    var calls = 0
    var pauseSource = false
    var sourceContinuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { sourceContinuation != nil }
    init(first: RecordingResourceDouble, second: RecordingResourceDouble) { self.first = first; self.second = second }
    func pauseFirstSource() { pauseSource = true }
    func make() async throws -> any ScreenRecordingResource {
        calls += 1
        let resource = calls == 1 ? first : second
        if calls == 1, pauseSource { await withCheckedContinuation { sourceContinuation = $0 } }
        return resource
    }
    func releaseSource() { sourceContinuation?.resume(); sourceContinuation = nil }
}

private actor RecordingResourceDouble: ScreenRecordingResource {
    nonisolated let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
    var cleanup: @Sendable (URL) async -> Void = { _ in }
    func setCleanup(_ cleanup: @escaping @Sendable (URL) async -> Void) { self.cleanup = cleanup }
    var startCount = 0
    var finishCount = 0
    var cancelCount = 0
    var startShouldFail = false
    var finishShouldFail = false
    var holdStart = false
    var holdFinish = false
    var holdCancel = false
    var startContinuation: CheckedContinuation<Void, Never>?
    var finishContinuation: CheckedContinuation<Void, Never>?
    var cancelContinuation: CheckedContinuation<Void, Never>?
    var isStartWaiting: Bool { startContinuation != nil }
    var isFinishWaiting: Bool { finishContinuation != nil }
    var isCancelWaiting: Bool { cancelContinuation != nil }
    func pauseStart() { holdStart = true }
    func pauseFinish() { holdFinish = true }
    func pauseCancel() { holdCancel = true }
    func failStart() { startShouldFail = true }
    func failFinish() { finishShouldFail = true }
    func start() async throws {
        startCount += 1
        if holdStart, startCount == 1 { await withCheckedContinuation { startContinuation = $0 } }
        if startShouldFail { throw ScreenCaptureError.writerFailed }
    }
    func finish() async throws -> URL {
        finishCount += 1
        if holdFinish, finishCount == 1 { await withCheckedContinuation { finishContinuation = $0 } }
        if finishShouldFail { throw ScreenCaptureError.writerFailed }
        return destination
    }
    func cancel() async {
        cancelCount += 1
        if holdCancel, cancelCount == 1 { await withCheckedContinuation { cancelContinuation = $0 } }
        await cleanup(destination)
    }
    func releaseStart() { startContinuation?.resume(); startContinuation = nil }
    func releaseFinish() { finishContinuation?.resume(); finishContinuation = nil }
    func releaseCancel() { cancelContinuation?.resume(); cancelContinuation = nil }
}

private actor RecordingDeletionProbe {
    var destinations: [URL] = []
    func record(_ url: URL) { destinations.append(url) }
}

private actor RecordingStreamProbe {
    var stream: SCStream?
    func record(_ stream: SCStream) { self.stream = stream }
}
