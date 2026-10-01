import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

final class RuntimeTranslationRequestControllerTests: XCTestCase {
    private var settings: TranslationSettings {
        TranslationSettings(apiKey: "synthetic-placeholder", endpointURLString: "https://example.invalid/translation")
    }

    @MainActor
    func testLeavingPageCancelsRequestAndIgnoresCancellationFailure() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        XCTAssertTrue(controller.submit("hello", settings: settings))
        await waitUntil { await client.pendingCount == 1 }
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
        await client.complete(0, with: .failure(URLError(.cancelled)))
        await waitUntil { await client.completedCount == 1 }
        await drainTasks()
        XCTAssertEqual(controller.state, .idle, "Page cancellation cannot display a network error")
        let cancelled = await client.cancelledRequests
        XCTAssertEqual(cancelled, [0], "Cancellation must reach the actual provider HTTP boundary")
    }

    @MainActor
    func testIgnoredCancellationSuccessCannotReplaceNewRequest() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        controller.submit("request A", settings: settings)
        await waitUntil { await client.pendingCount == 1 }
        controller.cancel()
        XCTAssertTrue(controller.submit("request B", settings: settings))
        await waitUntil { await client.pendingCount == 2 }
        await client.complete(0, with: .success(response("old response")))
        await waitUntil { await client.completedCount == 1 }
        await drainTasks()
        XCTAssertEqual(controller.state, .translating)
        XCTAssertEqual(controller.translatedOriginalText, "")
        await client.complete(1, with: .success(response("new response")))
        await waitUntil { controller.state == .translated("new response") }
        XCTAssertEqual(controller.translatedOriginalText, "request B")
    }

    @MainActor
    func testIgnoredCancellationFailureCannotReplaceNewRequest() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        controller.submit("request A", settings: settings)
        await waitUntil { await client.pendingCount == 1 }
        controller.cancel()
        controller.submit("request B", settings: settings)
        await waitUntil { await client.pendingCount == 2 }
        await client.complete(0, with: .failure(URLError(.timedOut)))
        await waitUntil { await client.completedCount == 1 }
        await drainTasks()
        XCTAssertEqual(controller.state, .translating)
        await client.complete(1, with: .success(response("new response")))
        await waitUntil { controller.state == .translated("new response") }
    }

    @MainActor
    func testDuplicateSubmissionAndInvalidInputKeepExistingGuard() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        XCTAssertFalse(controller.submit(" ", settings: settings))
        XCTAssertFalse(controller.submit("hello", settings: TranslationSettings()))
        XCTAssertTrue(controller.submit("hello", settings: settings))
        XCTAssertFalse(controller.submit("second", settings: settings))
        await waitUntil { await client.pendingCount == 1 }
        let requests = await client.requestCount
        XCTAssertEqual(requests, 1)
        await client.complete(0, with: .success(response("你好")))
        await waitUntil { controller.state == .translated("你好") }
    }

    @MainActor
    func testNormalCompletionKeepsOriginalTextAndCompletedOutputOnDisappear() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        controller.submit("  hello\n", settings: settings)
        await waitUntil { await client.pendingCount == 1 }
        await client.complete(0, with: .success(response("你好")))
        await waitUntil { controller.state == .translated("你好") }
        XCTAssertEqual(controller.translatedOriginalText, "hello")
        controller.cancel()
        XCTAssertEqual(controller.state, .translated("你好"), "Only an in-flight request is reset on disappearance")
    }

    @MainActor
    func testRealProviderNetworkFailureKeepsExistingUserMessage() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        controller.submit("hello", settings: settings)
        await waitUntil { await client.pendingCount == 1 }
        await client.complete(0, with: .failure(URLError(.notConnectedToInternet)))
        await waitUntil { controller.state == .failed("无法连接到百炼服务，请检查网络后重试。") }
    }

    @MainActor
    func testCancellationBeforeTaskStartsDoesNotSendHTTPRequest() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        let controller = makeController(client)
        controller.submit("hello", settings: settings)
        controller.cancel()
        await drainTasks()
        let requests = await client.requestCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(controller.state, .idle)
        // 如果退化为发送了请求，也释放替身，避免测试自身留下悬挂任务。
        if requests > 0 { await client.complete(0, with: .failure(URLError(.cancelled))) }
    }

    @MainActor
    func testRequestDoesNotRetainClosedPageController() async {
        let client = SuspendedRuntimeTranslationHTTPClient()
        var controller: RuntimeTranslationRequestController? = makeController(client)
        let releasedController = { [weak controller] in controller }
        controller?.submit("hello", settings: settings)
        await waitUntil { await client.pendingCount == 1 }
        controller = nil
        XCTAssertNil(releasedController())
        await client.complete(0, with: .success(response("late response")))
        await waitUntil { await client.completedCount == 1 }
        let cancelled = await client.cancelledRequests
        XCTAssertEqual(cancelled, [0])
    }

    @MainActor
    private func makeController(_ client: SuspendedRuntimeTranslationHTTPClient) -> RuntimeTranslationRequestController {
        RuntimeTranslationRequestController { configuration in
            BailianTranslationProvider(configuration: configuration, httpClient: client)
        }
    }

    private func response(_ text: String) -> TranslationHTTPResponse {
        TranslationHTTPResponse(data: Data("{\"choices\":[{\"message\":{\"content\":\"\(text)\"}}]}".utf8), statusCode: 200)
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Expected translation boundary was not reached", file: file, line: line)
    }

    @MainActor
    private func drainTasks() async { for _ in 0..<100 { await Task.yield() } }
}

private actor SuspendedRuntimeTranslationHTTPClient: TranslationHTTPClient {
    var requestCount = 0
    var completedCount = 0
    var cancelledRequests: [Int] = []
    var continuations: [Int: CheckedContinuation<TranslationHTTPResponse, Error>] = [:]
    var pendingCount: Int { continuations.count }

    func send(_ request: URLRequest) async throws -> TranslationHTTPResponse {
        let index = requestCount
        requestCount += 1
        defer {
            completedCount += 1
            if Task.isCancelled { cancelledRequests.append(index) }
        }
        // 故意忽略取消，确保产品不能仅依赖 URLSession 对取消的合作。
        return try await withCheckedThrowingContinuation { continuations[index] = $0 }
    }

    func complete(_ index: Int, with result: Result<TranslationHTTPResponse, Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}
