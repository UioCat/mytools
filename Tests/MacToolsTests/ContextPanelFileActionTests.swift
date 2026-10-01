import MacToolsCore
import XCTest
@testable import MacTools

@MainActor
final class ContextPanelFileActionTests: XCTestCase {
    func testControllerFailureKeepsCurrentInteractionAndShowsError() async {
        let controller = makeController(execute: { _, _ in throw FileActionError.invalidFolderPath("synthetic-private-path") })
        let id = UUID()
        var dismissed = 0
        controller.onDismiss = { dismissed += 1 }
        controller.beginInteraction(id: id, at: 10)
        let item = ClipboardClassifier().classify(payload: ClipboardPayload(text: "synthetic"), sourceApp: nil)
        _ = controller.performFileAction(.openTerminal, item: item, windowLayoutButtons: [])
        await controller.fileActionTask?.value
        XCTAssertTrue(controller.acceptsResult(for: id))
        XCTAssertEqual(dismissed, 0)
        XCTAssertEqual(controller.fileActionModel.failureMessage, "无法在终端打开，请检查目录或系统权限后重试。")
    }

    func testControllerRejectsLateEffectAfterNewInteraction() async {
        let execution = SuspendedFileAction()
        var effects: [ContextPanelFileActionEffect] = []
        let controller = makeController(execute: { _, _ in try await execution.perform() }, present: { effects.append($0) })
        controller.beginInteraction(id: UUID(), at: 10)
        let item = ClipboardClassifier().classify(payload: ClipboardPayload(text: "synthetic"), sourceApp: nil)
        _ = controller.performFileAction(.createNewFile, item: item, windowLayoutButtons: [])
        let pending = controller.fileActionTask
        await execution.waitUntilStarted()
        let replacement = UUID()
        controller.beginInteraction(id: replacement, at: 11)
        await execution.finish(.success(.copyPath("synthetic")))
        await pending?.value
        XCTAssertTrue(effects.isEmpty)
        XCTAssertTrue(controller.acceptsResult(for: replacement))
        XCTAssertNil(controller.fileActionModel.failureMessage)
    }

    func testControllerRetainsFirstPendingTaskWhenAnotherActionIsQueued() async {
        let execution = SuspendedFileAction()
        var executions = 0
        var observedCancellation = false
        let controller = makeController(execute: { _, _ in
            executions += 1
            let result = try await execution.perform()
            observedCancellation = Task.isCancelled
            return result
        })
        controller.beginInteraction(id: UUID(), at: 10)
        let item = ClipboardClassifier().classify(payload: ClipboardPayload(text: "synthetic"), sourceApp: nil)
        _ = controller.performFileAction(.createNewFile, item: item, windowLayoutButtons: [])
        _ = controller.performFileAction(.openTerminal, item: item, windowLayoutButtons: [])
        await execution.waitUntilStarted()
        XCTAssertEqual(executions, 1)
        controller.cancelInteraction()
        await execution.finish(.success(.none))
        await controller.fileActionTask?.value
        XCTAssertTrue(observedCancellation, "Dismissal must cancel the original pending task")
        XCTAssertNil(controller.fileActionModel.failureMessage)
    }

    func testControllerPresentsSuccessfulEffectOnMainActorThenDismisses() async {
        var effects: [ContextPanelFileActionEffect] = []
        let controller = makeController(execute: { _, _ in .copyPath("synthetic") }, present: {
            XCTAssertTrue(Thread.isMainThread)
            effects.append($0)
        })
        let id = UUID()
        controller.beginInteraction(id: id, at: 10)
        let item = ClipboardClassifier().classify(payload: ClipboardPayload(text: "synthetic"), sourceApp: nil)
        _ = controller.performFileAction(.copyPath, item: item, windowLayoutButtons: [])
        await controller.fileActionTask?.value
        XCTAssertEqual(effects, [.copyPath("synthetic")])
        XCTAssertFalse(controller.acceptsResult(for: id))
    }

    func testTerminalAndCreateFileUseBackgroundWorkerWithRealTemporaryFolder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runner = RecordingFileActionRunner()
        let files = RecordingFileActionFileManager()
        let worker = ContextPanelFileActionWorker(service: FileActionService(workspace: UnusedFileActionWorkspace(),
            processRunner: runner, fileManager: files))
        let item = ClipboardClassifier().classify(payload: ClipboardPayload(fileURLs: [directory]), sourceApp: nil)
        _ = try await worker.perform(.openTerminal, item: item)
        let effect = try await worker.perform(.createNewFile, item: item)
        XCTAssertEqual(runner.calledOnMainThread, [false])
        XCTAssertFalse(files.calledOnMainThread.isEmpty)
        XCTAssertFalse(files.calledOnMainThread.contains(true))
        guard case .reveal(let url) = effect else { return XCTFail("Created file must be returned for presentation") }
        XCTAssertEqual(url.lastPathComponent, "Untitled.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPendingActionDisablesActionsAndDuplicateRequestIsIgnored() async {
        let execution = SuspendedFileAction()
        let model = ContextPanelFileActionModel()
        var completed = 0
        let first = Task { await model.perform(.createNewFile, execute: { try await execution.perform() },
            isCurrent: { true }, onSuccess: { _ in completed += 1 }, logFailure: { _ in }) }
        await execution.waitUntilStarted()
        XCTAssertTrue(model.isExecuting)
        await model.perform(.openTerminal, execute: { XCTFail("Duplicate action"); return .none },
            isCurrent: { true }, onSuccess: { _ in completed += 1 }, logFailure: { _ in })
        await execution.finish(.success(.none))
        await first.value
        XCTAssertFalse(model.isExecuting)
        XCTAssertEqual(completed, 1)
    }

    func testDismissalOrReplacementDiscardsLateCompletionAndFailure() async {
        for result in [Result<ContextPanelFileActionEffect, Error>.success(.none), .failure(FileActionError.invalidFolderPath("synthetic-private-path"))] {
            let execution = SuspendedFileAction()
            let model = ContextPanelFileActionModel()
            var current = true
            var successes = 0
            let pending = Task { await model.perform(.openTerminal, execute: { try await execution.perform() },
                isCurrent: { current }, onSuccess: { _ in successes += 1 }, logFailure: { _ in }) }
            await execution.waitUntilStarted()
            current = false
            model.reset()
            await execution.finish(result)
            await pending.value
            XCTAssertEqual(successes, 0)
            XCTAssertFalse(model.isExecuting)
            XCTAssertNil(model.failureMessage)
        }
    }

    func testFailureRemainsVisibleAndLogsOnlyErrorTypeWithoutPath() async {
        let model = ContextPanelFileActionModel()
        var logs: [String] = []
        var completed = false
        await model.perform(.openTerminal,
            execute: { throw FileActionError.invalidFolderPath("synthetic-private-path") },
            isCurrent: { true }, onSuccess: { _ in completed = true }, logFailure: { logs.append($0) })
        XCTAssertFalse(completed)
        XCTAssertEqual(model.failureMessage, "无法在终端打开，请检查目录或系统权限后重试。")
        XCTAssertEqual(logs.count, 1)
        XCTAssertFalse(logs.joined().contains("synthetic-private-path"))
        XCTAssertTrue(logs.joined().contains("FileActionError"))
    }

    private func makeController(
        execute: @escaping (SuperPanelActionID, ClipboardItem) async throws -> ContextPanelFileActionEffect,
        present: @escaping (ContextPanelFileActionEffect) -> Void = { _ in }
    ) -> ContextPanelController {
        let logger = Logger(debugLogDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return ContextPanelController(fileActionService: FileActionService(workspace: UnusedFileActionWorkspace()),
            pasteboard: UnusedFileActionPasteboard(), windowLayoutService: SystemWindowLayoutService(logger: logger),
            windowLayoutButtons: { [] }, speechController: TranslationSpeechController(engine: UnusedFileActionSpeech()),
            logger: logger, executeFileAction: execute, presentFileEffect: present, outsideClickMonitoringEnabled: false)
    }
}

private struct UnusedFileActionPasteboard: WritablePasteboard {
    func writeText(_ text: String) { XCTFail("Presentation effect is injected") }
    func writeFileURL(_ url: URL) { XCTFail("Presentation effect is injected") }
    func writeImageData(_ data: Data) throws { XCTFail("Presentation effect is injected") }
}

@MainActor
private final class UnusedFileActionSpeech: TranslationSpeechEngine {
    func speak(_ request: TranslationSpeechRequest, completion: @escaping TranslationSpeechCompletion) { XCTFail("File action must not speak") }
    func stop() {}
}

private final class RecordingFileActionRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    var calledOnMainThread: [Bool] { lock.withLock { calls } }
    func run(_ executableURL: URL, arguments: [String]) throws { lock.withLock { calls.append(Thread.isMainThread) } }
}

private final class RecordingFileActionFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    var calledOnMainThread: [Bool] { lock.withLock { calls } }
    override func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        lock.withLock { calls.append(Thread.isMainThread) }
        return super.fileExists(atPath: path, isDirectory: isDirectory)
    }
    override func fileExists(atPath path: String) -> Bool {
        lock.withLock { calls.append(Thread.isMainThread) }
        return super.fileExists(atPath: path)
    }
}

private struct UnusedFileActionWorkspace: WorkspaceOpening {
    func open(_ url: URL) { XCTFail("Worker must return presentation effects") }
    func reveal(_ url: URL) { XCTFail("Worker must return presentation effects") }
}

private actor SuspendedFileAction {
    private var pending: CheckedContinuation<ContextPanelFileActionEffect, Error>?
    private var started: CheckedContinuation<Void, Never>?
    func perform() async throws -> ContextPanelFileActionEffect {
        try await withCheckedThrowingContinuation { pending = $0; started?.resume(); started = nil }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ result: Result<ContextPanelFileActionEffect, Error>) { pending?.resume(with: result); pending = nil }
}
