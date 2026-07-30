# MacTools P1 性能风险治理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除剪贴板图片行和剪贴板面板动作中的主线程文件、图片及数据库 I/O，同时保持现有复制、自动粘贴、收藏、删除和清空语义。

**Architecture:** SwiftUI 图片行只构造不访问文件系统的请求值，文件属性解析、缓存查询和 ImageIO 解码统一进入 utility detached task。剪贴板面板保留 MainActor 展示状态，由单一 `ClipboardPanelWorker` actor 串行执行仓储、Payload GC 和图片准备；MainActor 仅写系统剪贴板、发布最新代次结果及驱动面板/目标应用。

**Tech Stack:** Swift 5.10、Swift Concurrency、SwiftUI、AppKit、ImageIO、GRDB.swift、XCTest、Swift Package Manager。

## Global Constraints

- 目标平台保持 macOS 26.0，不新增外部依赖或 Xcode 工程。
- `Sources/MacToolsCore/UI` 不得引用数据库、仓储、Payload、同步目录或凭据实现。
- 数据库、图片文件读取、PNG 规范化和 Payload GC 不得阻塞 MainActor。
- 收藏和置顶记录不得被“清除非收藏项”或普通历史裁剪删除。
- 剪贴板写入成功后才能标记使用；复制失败不得关闭面板、激活目标应用或发送 Command+V。
- 自动粘贴权限不足时保留已成功复制和标记使用的结果，但不得发送 Command+V。
- 新的粘贴激活请求继续取消旧 `PasteActivationAttempt`，一次请求最多发送一次 Command+V。
- 行为变更必须遵循 RED → GREEN → REFACTOR；每个测试必须先观察到预期失败。
- P1 两项任务及任务级评审完成后，必须通过完整 P1 验证门禁，才允许开始 P2。

## File Structure

| 文件 | 职责 |
| --- | --- |
| `Sources/MacToolsCore/UI/Clipboard/ClipboardRowView.swift` | 定义纯图片预览请求、后台 resolver/loader、缓存和 SwiftUI 结果发布 |
| `Tests/MacToolsCoreTests/ClipboardListViewTests.swift` | 验证请求构造不触发 I/O、后台属性解析、缓存失效和过期结果抑制 |
| `Sources/MacToolsCore/Paste/PasteActionService.swift` | 把可后台准备的剪贴板内容与 MainActor 系统写入拆开 |
| `Tests/MacToolsCoreTests/PasteActionServiceTests.swift` | 验证图片只准备一次 PNG、写入失败不发送粘贴及原有文本/文件契约 |
| `Sources/MacTools/Application/AppEnvironmentWorkers.swift` | 新增串行执行仓储和图片准备的 `ClipboardPanelWorker` actor |
| `Sources/MacTools/Features/Clipboard/ClipboardPanelModel.swift` | 管理异步请求代次、发布列表和成功后的本地变更通知 |
| `Sources/MacTools/Features/Clipboard/ClipboardPasteFlow.swift` | 封装复制成功后才检查权限、隐藏面板和激活目标的自动粘贴顺序 |
| `Sources/MacTools/Application/AppEnvironment.swift` | 注入工作器并把复制/自动粘贴入口改为异步流程 |
| `Sources/MacTools/Application/RuntimeViews.swift` | 从同步 SwiftUI 回调启动结构化的 MainActor Task |
| `Package.swift` | 增加可执行层行为测试 target `MacToolsTests` |
| `Tests/MacToolsTests/TestSupport.swift` | 提供完整的剪贴板项、pasteboard、event sender、logger 目录和事件记录测试边界 |
| `Tests/MacToolsTests/ClipboardPanelModelTests.swift` | 使用真实内存仓储和受控边界验证异步面板状态 |
| `Tests/MacToolsTests/ClipboardPasteFlowTests.swift` | 验证复制失败、权限不足和成功自动粘贴的可见副作用顺序 |
| `docs/superpowers/specs/2026-07-30-performance-risk-hardening-design.md` | P1 门禁通过后更新风险状态与验证证据 |

---

### Task 1: 图片预览请求异步解析

**Files:**

- Modify: `Sources/MacToolsCore/UI/Clipboard/ClipboardRowView.swift`
- Modify: `Tests/MacToolsCoreTests/ClipboardListViewTests.swift`

**Interfaces:**

- Consumes: `ClipboardItem.kind`、`thumbnailPath`、`cachedFilePath`、`originalPath`、`contentHash`；`ClipboardImagePreviewCache.preview(for:)`。
- Produces:

```swift
struct ClipboardImagePreviewRequest: Equatable, Hashable, Sendable {
    let path: String
    let contentHash: String?

    static func request(for item: ClipboardItem) -> Self?
}

struct ClipboardImagePreviewFileAttributes: Equatable, Sendable {
    let byteCount: Int64?
    let modificationDate: Date?
}

struct ClipboardImagePreviewLoader: Sendable {
    typealias AttributesProvider =
        @Sendable (String) -> ClipboardImagePreviewFileAttributes?
    typealias PreviewProvider =
        @Sendable (ClipboardImagePreviewSource) -> ClipboardLoadedImagePreview?

    init(
        attributesProvider: @escaping AttributesProvider,
        previewProvider: @escaping PreviewProvider
    )

    func load(_ request: ClipboardImagePreviewRequest) async
        -> ClipboardLoadedImagePreview?

    static let live: ClipboardImagePreviewLoader
}

extension ClipboardImagePreviewSource {
    static func resolve(
        _ request: ClipboardImagePreviewRequest,
        attributes: ClipboardImagePreviewFileAttributes?
    ) -> ClipboardImagePreviewSource
}
```

- `ClipboardImagePreviewSource` 只接受 request 与已解析属性生成缓存键，不再接受 `ClipboardItem`，也不直接访问 `FileManager`。
- `ClipboardLoadedImagePreview` 记录原始 request；SwiftUI 只在 `loaded.request == currentRequest` 时展示结果。

- [ ] **Step 1: 写失败测试，证明 SwiftUI 请求构造不读取文件属性**

在 `ClipboardListViewTests` 中删除直接调用 `ClipboardImagePreviewSource.source(for:)` 的旧断言，先写纯请求测试：

```swift
func testImagePreviewRequestSelectsPathWithoutResolvingFileAttributes() throws {
    let request = try XCTUnwrap(
        ClipboardImagePreviewRequest.request(
            for: makeImageItem(
                thumbnailPath: "/not-mounted/thumb.png",
                cachedFilePath: "/cache/image.png",
                originalPath: "/original/image.png",
                contentHash: "  abc123  "
            )
        )
    )

    XCTAssertEqual(request.path, "/not-mounted/thumb.png")
    XCTAssertEqual(request.contentHash, "abc123")
}
```

该测试捕获的回归是 request 构造重新调用文件系统，或改变缩略图优先级/哈希规范化。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```sh
swift test --filter ClipboardListViewTests/testImagePreviewRequestSelectsPathWithoutResolvingFileAttributes
```

Expected: 编译失败，提示 `ClipboardImagePreviewRequest` 尚未定义。

- [ ] **Step 3: 最小实现纯请求值**

实现 `ClipboardImagePreviewRequest.request(for:)`：仅对 `.imageData`、`.imageFile` 生效；按 thumbnail、cached、original 顺序选择首个非空路径；把空白哈希规范为 `nil`。将 `rowContent` 的 `.task(id:)`、`currentImagePreview` 和回写校验全部改为使用 request。

- [ ] **Step 4: 写失败测试，证明属性读取和预览提供器不在主线程执行**

在测试文件加入只属于测试的锁保护记录器：

```swift
private final class LockedThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func append(_ value: Bool) {
        lock.withLock { values.append(value) }
    }

    var snapshot: [Bool] {
        lock.withLock { values }
    }
}
```

测试从 MainActor 调用 loader，并让两个边界分别记录线程：

```swift
@MainActor
func testImagePreviewLoaderResolvesAndDecodesOffMainThread() async throws {
    let observations = LockedThreadObservation()
    let request = ClipboardImagePreviewRequest(
        path: "/virtual/image.png",
        contentHash: "hash"
    )
    let loader = ClipboardImagePreviewLoader(
        attributesProvider: { _ in
            observations.append(Thread.isMainThread)
            return .init(
                byteCount: 4,
                modificationDate: Date(timeIntervalSinceReferenceDate: 10)
            )
        },
        previewProvider: { _ in
            observations.append(Thread.isMainThread)
            return nil
        }
    )

    _ = await loader.load(request)

    XCTAssertEqual(observations.snapshot, [false, false])
}
```

该测试捕获的回归是把 resolver 或 ImageIO/cache 调用移回继承 MainActor 的任务。

- [ ] **Step 5: 运行测试并确认 RED**

Run:

```sh
swift test --filter ClipboardListViewTests/testImagePreviewLoaderResolvesAndDecodesOffMainThread
```

Expected: 编译失败，提示 loader 接口不存在。

- [ ] **Step 6: 实现 utility detached loader 与取消传播**

`ClipboardImagePreviewLoader.load` 创建 `.utility` 的 `Task.detached`，在同一后台闭包中执行 attributes provider、生成 source、调用 preview provider；使用 `withTaskCancellationHandler` 把外层取消转发给 detached task。默认 provider 使用 `FileManager.default.attributesOfItem(atPath:)`，转换为 `ClipboardImagePreviewFileAttributes`；默认 preview provider 使用共享 cache。

SwiftUI 加载逻辑固定为：

```swift
let request = imagePreviewRequest
let preview = await ClipboardImagePreviewLoader.live.load(request)
guard !Task.isCancelled, imagePreviewRequest == request else { return }
loadedImagePreview = preview
```

取消只抑制结果发布，不承诺中断已经进入系统调用的 I/O。

- [ ] **Step 7: 写失败测试，固定缓存键和过期结果语义**

用手工属性值验证缓存键：

```swift
func testResolvedImagePreviewCacheKeyTracksAttributesAndContentHash() {
    let request = ClipboardImagePreviewRequest(
        path: "/cache/image.png",
        contentHash: "first"
    )
    let first = ClipboardImagePreviewSource.resolve(
        request,
        attributes: .init(
            byteCount: 1,
            modificationDate: Date(timeIntervalSinceReferenceDate: 10)
        )
    )
    let changed = ClipboardImagePreviewSource.resolve(
        .init(path: request.path, contentHash: "second"),
        attributes: .init(
            byteCount: 4,
            modificationDate: Date(timeIntervalSinceReferenceDate: 20)
        )
    )

    XCTAssertEqual(
        first.cacheKey,
        "/cache/image.png|size:1|modified:10.0|hash:first"
    )
    XCTAssertNotEqual(first.cacheKey, changed.cacheKey)
}
```

增加一个延迟 provider 测试：

```swift
@MainActor
func testCancelledImagePreviewLoadDoesNotReturnDecodedPreview() async throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("preview.png")
    try writeTestPNG(to: fileURL, width: 2, height: 3)
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let cache = ClipboardImagePreviewCache(
        configuration: .init(countLimit: 1, totalCostLimit: 1_024 * 1_024)
    )
    let loader = ClipboardImagePreviewLoader(
        attributesProvider: { _ in
            .init(
                byteCount: 64,
                modificationDate: Date(timeIntervalSinceReferenceDate: 10)
            )
        },
        previewProvider: { source in
            started.signal()
            release.wait()
            return cache.preview(for: source)
        }
    )
    let task = Task {
        await loader.load(.init(path: fileURL.path, contentHash: "hash"))
    }
    await Task.detached { started.wait() }.value

    task.cancel()
    release.signal()

    XCTAssertNil(await task.value)
}
```

它捕获取消后仍返回已解码结果的回归，而不是只验证 provider 本身。

- [ ] **Step 8: 运行 Task 1 聚焦测试并重构**

Run:

```sh
swift test --filter ClipboardListViewTests
```

Expected: 所有 `ClipboardListViewTests` 通过；输出无新增 warning。删除旧的同步 `source(for item:)` 和 `cacheKey(forPath:)` 入口，确认 `rg -n 'attributesOfItem' Sources/MacToolsCore/UI/Clipboard/ClipboardRowView.swift` 只命中 live loader 的 detached 工作闭包。

- [ ] **Step 9: 提交 Task 1**

```sh
git add Sources/MacToolsCore/UI/Clipboard/ClipboardRowView.swift Tests/MacToolsCoreTests/ClipboardListViewTests.swift
git commit -m "修复剪贴板图片预览主线程文件查询" \
  -m "• 将 SwiftUI 图片来源改为纯值请求，避免 body 读取文件属性
• 在 utility detached 任务解析缓存键并解码缩略图，保留取消和过期结果保护
• 增加线程、缓存失效和取消行为测试
• 验证：swift test --filter ClipboardListViewTests 通过"
```

---

### Task 2: 面板工作器与复制/自动粘贴时序

**Files:**

- Modify: `Package.swift`
- Modify: `Sources/MacToolsCore/Paste/PasteActionService.swift`
- Modify: `Tests/MacToolsCoreTests/PasteActionServiceTests.swift`
- Modify: `Sources/MacTools/Application/AppEnvironmentWorkers.swift`
- Modify: `Sources/MacTools/Features/Clipboard/ClipboardPanelModel.swift`
- Create: `Sources/MacTools/Features/Clipboard/ClipboardPasteFlow.swift`
- Modify: `Sources/MacTools/Application/AppEnvironment.swift`
- Modify: `Sources/MacTools/Application/RuntimeViews.swift`
- Create: `Tests/MacToolsTests/TestSupport.swift`
- Create: `Tests/MacToolsTests/ClipboardPanelModelTests.swift`
- Create: `Tests/MacToolsTests/ClipboardPasteFlowTests.swift`

**Interfaces:**

- Consumes: `ClipboardRepository` 的 `search`、`markUsed`、`setFavorite`、`delete`、`deleteAllNonFavorites`；Task 1 不提供此任务的运行时依赖。
- Produces:

```swift
public enum PreparedPasteboardContent: Equatable, Sendable {
    case text(String)
    case fileURL(URL)
    case png(Data)
}

extension PasteActionService {
    public static func prepareContent(
        for item: ClipboardItem
    ) throws -> PreparedPasteboardContent

    public func write(_ content: PreparedPasteboardContent) throws
}

protocol ClipboardPanelWorking: Sendable {
    func load(limit: Int) async throws -> [ClipboardItem]
    func markUsedAndLoad(
        id: UUID,
        at date: Date,
        limit: Int
    ) async throws -> [ClipboardItem]
    func setFavoriteAndLoad(
        id: UUID,
        isFavorite: Bool,
        historyLimit: Int,
        limit: Int
    ) async throws -> [ClipboardItem]
    func deleteAndLoad(
        id: UUID,
        limit: Int
    ) async throws -> [ClipboardItem]
    func clearNonFavoritesAndLoad(
        limit: Int
    ) async throws -> [ClipboardItem]
    func prepareContent(
        for item: ClipboardItem
    ) async throws -> PreparedPasteboardContent
}

@MainActor
final class ClipboardPanelModel: ObservableObject {
    init(
        worker: any ClipboardPanelWorking,
        pasteActionService: PasteActionService,
        logger: Logger,
        historyLimit: @escaping () -> Int,
        pageSize: Int = 1_000,
        onLocalChange: @escaping () -> Void = {}
    )
}

@MainActor
struct ClipboardPasteFlow {
    init(
        copy: @escaping (ClipboardItem) async throws -> Void,
        canPostPasteEvent: @escaping () -> Bool,
        showPermissionAlert: @escaping () -> Void,
        hidePanel: @escaping () -> Void,
        activateAndPaste: @escaping () -> Void,
        reportError: @escaping (Error) -> Void
    )

    func run(_ item: ClipboardItem) async
}
```

- `ClipboardPanelWorker` 是 `ClipboardPanelWorking` 的 actor 实现。每个 mutation 与随后的 `search("", limit:)` 在同一个 actor 方法中连续执行，中间不跨 `await`。
- `ClipboardPanelModel.refresh()`、`copy(_:)`、`toggleFavorite(_:)`、`delete(_:)`、`clearNonFavorites()` 改为 async；每次操作取得递增 generation，只有最新 generation 可以发布 items。
- `ClipboardPasteFlow.run(item:)` 在 MainActor 严格执行 `await copy → permission → hide → activateAndPaste`。

- [ ] **Step 1: 写失败测试，定义后台图片准备和 MainActor 写入边界**

在 `PasteActionServiceTests` 中先写：

```swift
func testPrepareImageContentReturnsNormalizedPNG() throws {
    let tiffURL = try temporaryImageURL(data: try makeTIFFImageData())
    defer { try? FileManager.default.removeItem(at: tiffURL.deletingLastPathComponent()) }

    let content = try PasteActionService.prepareContent(
        for: .testItem(kind: .imageData, cachedFilePath: tiffURL.path)
    )

    guard case let .png(data) = content else {
        return XCTFail("expected prepared PNG")
    }
    XCTAssertEqual(
        data.prefix(8),
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    )
}

func testWritePreparedPNGDoesNotReadOrNormalizeTheSourceAgain() throws {
    let pasteboard = FakeWritablePasteboard()
    let service = PasteActionService(
        pasteboard: pasteboard,
        eventSender: FakePasteEventSender()
    )
    let png = Data([0x89, 0x50, 0x4E, 0x47])

    try service.write(.png(png))

    XCTAssertEqual(pasteboard.operations, [.writeImageData(png)])
}
```

这两个测试分别捕获图片准备仍留在系统剪贴板写入路径，以及主线程重复读取/规范化图片的回归。

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```sh
swift test --filter PasteActionServiceTests
```

Expected: 编译失败，提示 `PreparedPasteboardContent`、`prepareContent` 和 `write` 尚未定义。

- [ ] **Step 3: 最小实现准备/写入两阶段**

`prepareContent(for:)` 保持文本、图片、文件 URL 优先级；图片在调用线程执行 `Data(contentsOf:)` 和 `ImageDataNormalizer.pngData`，失败抛 `.invalidImageData`。`write(_:)` 只调用 `WritablePasteboard`，不得访问路径或执行图片解码。保留 `copy(_:)` 和 `copyAndPaste(_:)` 兼容入口，内部组合 prepare/write；面板新流程不得调用这些同步兼容入口。

- [ ] **Step 4: 新增可执行层测试 target 并确认可导入真实实现**

在 `Package.swift` 增加：

```swift
.testTarget(
    name: "MacToolsTests",
    dependencies: ["MacTools", "MacToolsCore"]
)
```

创建 `Tests/MacToolsTests/TestSupport.swift`，使用 `@testable import MacToolsCore` 并定义完整的系统边界：

```swift
enum MacToolsTestError: Error {
    case expectedFailure
    case unexpectedCall
}

final class FakeWritablePasteboard: WritablePasteboard {
    enum Operation: Equatable {
        case writeText(String)
        case writeFileURL(URL)
        case writeImageData(Data)
    }

    var writeError: Error?
    private(set) var operations: [Operation] = []

    func writeText(_ text: String) {
        operations.append(.writeText(text))
    }

    func writeFileURL(_ url: URL) {
        operations.append(.writeFileURL(url))
    }

    func writeImageData(_ data: Data) throws {
        if let writeError { throw writeError }
        operations.append(.writeImageData(data))
    }
}

final class FakePasteEventSender: PasteEventSender {
    private(set) var sendPasteCount = 0
    func sendCopyShortcut() {}
    func sendPasteShortcut() { sendPasteCount += 1 }
}

@MainActor
final class EventRecorder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

func makeTestLogger() -> Logger {
    Logger(
        debugLogDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MacToolsTests-\(UUID().uuidString)",
                isDirectory: true
            )
    )
}

extension ClipboardItem {
    static func testItem(
        kind: ClipboardContentKind = .text,
        text: String? = "item",
        originalPath: String? = nil,
        cachedFilePath: String? = nil,
        isFavorite: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: text ?? originalPath ?? cachedFilePath ?? "item",
            searchableText: text ?? originalPath ?? cachedFilePath ?? "",
            text: text,
            originalPath: originalPath,
            cachedFilePath: cachedFilePath,
            thumbnailPath: nil,
            sourceApp: "Tests",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: isFavorite
        )
    }
}
```

创建 `Tests/MacToolsTests/ClipboardPanelModelTests.swift`，使用 `@testable import MacTools` 和 `@testable import MacToolsCore`。先运行：

```sh
swift test --filter ClipboardPanelModelTests
```

Expected: target 可以编译并报告 0 个已选择测试；若 SwiftPM 拒绝导入 executable target，不得改用源码字符串断言，改为把 `ClipboardPanelWorking` 和不含 AppKit 的代次协调器移动到 `MacToolsCore`，`ClipboardPanelWorker` 仍保留在 Application。

- [ ] **Step 5: 写失败测试，证明仓储 mutation 和返回快照由真实 actor 串行完成**

使用真实 `ClipboardDatabase.inMemory()` 和 `ClipboardRepository`：

```swift
func testClearNonFavoritesAndLoadKeepsFavoriteRecord() async throws {
    let database = try ClipboardDatabase.inMemory()
    let repository = ClipboardRepository(database: database)
    let favorite = ClipboardItem.testItem(text: "favorite", isFavorite: true)
    let ordinary = ClipboardItem.testItem(text: "ordinary")
    try repository.upsert(favorite)
    try repository.upsert(ordinary)
    let worker = ClipboardPanelWorker(repository: repository)

    let items = try await worker.clearNonFavoritesAndLoad(limit: 100)

    XCTAssertEqual(items.map(\.id), [favorite.id])
    XCTAssertEqual(try repository.item(id: favorite.id)?.id, favorite.id)
    XCTAssertNil(try repository.item(id: ordinary.id))
}
```

再增加 `markUsedAndLoad` 测试，断言返回项 `useCount == 1` 且 `lastUsedAt` 等于传入固定时间。测试捕获 mutation 与快照拆开后返回旧状态的回归。

- [ ] **Step 6: 运行 worker 测试并确认 RED**

Run:

```sh
swift test --filter ClipboardPanelModelTests/testClearNonFavoritesAndLoadKeepsFavoriteRecord
```

Expected: 编译失败，提示 `ClipboardPanelWorker` 尚未定义。

- [ ] **Step 7: 实现 `ClipboardPanelWorker`**

在 `AppEnvironmentWorkers.swift` 实现协议的 actor。`prepareContent(for:)` 调用 `PasteActionService.prepareContent(for:)`，因此图片文件读取和 PNG 规范化运行在 actor executor；所有仓储操作和由 repository 触发的 Payload GC 也在该 executor 执行。错误原样抛回 MainActor，不在 worker 吞掉。

- [ ] **Step 8: 写失败测试，证明旧读取不能覆盖更新状态**

测试中实现受控的 `ClipboardPanelWorking` fake，只把外部仓储边界替换为可控 continuation；断言真实 `ClipboardPanelModel` 的最终 items，而不是断言 fake 调用：

```swift
private actor ControlledClipboardPanelWorker: ClipboardPanelWorking {
    enum LoadResult: Sendable {
        case suspended([ClipboardItem])
        case immediate([ClipboardItem])
    }

    private var loadResults: [LoadResult]
    private var firstLoadIsSuspended = false
    private var firstLoadContinuation: CheckedContinuation<Void, Never>?

    init(loadResults: [LoadResult]) {
        self.loadResults = loadResults
    }

    func load(limit: Int) async throws -> [ClipboardItem] {
        guard !loadResults.isEmpty else {
            throw MacToolsTestError.unexpectedCall
        }
        switch loadResults.removeFirst() {
        case let .immediate(items):
            return items
        case let .suspended(items):
            firstLoadIsSuspended = true
            await withCheckedContinuation {
                firstLoadContinuation = $0
            }
            return items
        }
    }

    func waitUntilFirstLoadIsSuspended() async {
        while !firstLoadIsSuspended {
            await Task.yield()
        }
    }

    func resumeFirstLoad() {
        firstLoadContinuation?.resume()
        firstLoadContinuation = nil
    }

    func markUsedAndLoad(
        id: UUID,
        at date: Date,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func setFavoriteAndLoad(
        id: UUID,
        isFavorite: Bool,
        historyLimit: Int,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func deleteAndLoad(
        id: UUID,
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func clearNonFavoritesAndLoad(
        limit: Int
    ) async throws -> [ClipboardItem] {
        throw MacToolsTestError.unexpectedCall
    }

    func prepareContent(
        for item: ClipboardItem
    ) async throws -> PreparedPasteboardContent {
        throw MacToolsTestError.unexpectedCall
    }
}

@MainActor
func testOlderRefreshCannotOverwriteNewerRefresh() async throws {
    let old = ClipboardItem.testItem(text: "old")
    let newest = ClipboardItem.testItem(text: "new")
    let worker = ControlledClipboardPanelWorker(
        loadResults: [.suspended([old]), .immediate([newest])]
    )
    let model = ClipboardPanelModel(
        worker: worker,
        pasteActionService: PasteActionService(
            pasteboard: FakeWritablePasteboard(),
            eventSender: FakePasteEventSender()
        ),
        logger: makeTestLogger(),
        historyLimit: { 500 }
    )

    async let first: Void = model.refresh()
    await worker.waitUntilFirstLoadIsSuspended()
    await model.refresh()
    await worker.resumeFirstLoad()
    _ = await first

    XCTAssertEqual(model.items.map(\.id), [newest.id])
}
```

该测试捕获 generation 缺失或判断方向错误导致旧查询覆盖新页面的回归。

- [ ] **Step 9: 写失败测试，证明复制失败没有持久化成功副作用**

使用 worker fake 让 `prepareContent` 抛出固定错误；调用 `try await model.copy(item)` 后断言：

```swift
XCTAssertEqual(model.items, initialItems)
XCTAssertEqual(localChangeCount, 0)
XCTAssertTrue(pasteboard.operations.isEmpty)
```

再让 pasteboard 的 `writeImageData` 抛错，断言 `markUsedAndLoad` 未改变真实内存数据库中的 `useCount`。该测试捕获“先标记使用再写剪贴板”或失败后伪造成功的回归。

失败 fake 必须完整实现 `ClipboardPanelWorking`；除测试指定的 `prepareContent` 或 `markUsedAndLoad` 外，其余方法统一抛 `MacToolsTestError.unexpectedCall`。测试只断言 model、真实 repository 和 pasteboard 的用户可见状态，不断言 fake 自身存在。

- [ ] **Step 10: 实现异步 `ClipboardPanelModel`**

模型只持有 `any ClipboardPanelWorking`、`PasteActionService`、logger、historyLimit 和 onLocalChange。每个公开 async 操作调用私有 `nextGeneration()`；成功返回后用 `apply(items:generation:)` 发布。mutation 成功时只调用一次 `onLocalChange`。

`copy(_:)` 的固定顺序：

```swift
let content = try await worker.prepareContent(for: item)
try pasteActionService.write(content)
do {
    let items = try await worker.markUsedAndLoad(
        id: item.id,
        at: Date(),
        limit: pageSize
    )
    apply(items: items, generation: generation)
    onLocalChange()
} catch {
    await refresh()
    throw error
}
```

`prepareForPresentation()` 先递增 `presentationToken`，再启动一次 `Task { await refresh() }`。UI 回调使用 `Task { await model.toggleFavorite(item) }` 等形式，不把同步 I/O 带回 MainActor。

- [ ] **Step 11: 写失败测试，固定自动粘贴顺序和三个失败分支**

创建 `ClipboardPasteFlowTests`，用一个线程安全事件记录器记录真实 flow 触发的边界事件：

```swift
@MainActor
func testPasteFlowCopiesBeforePermissionHideAndActivation() async {
    let events = EventRecorder()
    let flow = ClipboardPasteFlow(
        copy: { _ in events.append("copy") },
        canPostPasteEvent: {
            events.append("permission")
            return true
        },
        showPermissionAlert: { events.append("alert") },
        hidePanel: { events.append("hide") },
        activateAndPaste: { events.append("activate") },
        reportError: { _ in events.append("error") }
    )

    await flow.run(.testItem(text: "hello"))

    XCTAssertEqual(events.values, ["copy", "permission", "hide", "activate"])
}
```

另写两个独立测试：

- copy 抛错时事件仅为 `["copy", "error"]`；
- 权限不足时事件为 `["copy", "permission", "alert"]`。

它们分别捕获复制失败仍隐藏/激活，以及权限不足仍发送粘贴的回归。

- [ ] **Step 12: 实现 flow 并接入 `AppEnvironment`**

`ClipboardPasteFlow` 是 MainActor 类型，只接受上述六个闭包。`AppEnvironment.copyFromPanel` 启动 MainActor Task 并 `try await clipboardModel.copy(item)`；`pasteFromPanel` 使用 flow。`activateAndPaste` 继续调用现有 `pasteAfterActivatingTarget`，因此 `PasteActivationAttempt` 的取消、激活通知、80 ms 延迟和 800 ms fallback 不变。

`AppEnvironment` 构造 `ClipboardPanelWorker(repository:)` 并注入 model；`RuntimeViews` 的刷新、收藏、删除和清空回调只负责启动 async Task。

- [ ] **Step 13: 运行 Task 2 聚焦测试并重构**

Run:

```sh
swift test --filter PasteActionServiceTests
swift test --filter ClipboardPanelModelTests
swift test --filter ClipboardPasteFlowTests
swift test --filter ClipboardRepositoryTests
```

Expected: 四组测试全部通过；没有真实 TCC、当前桌面或外部文件依赖。确认：

```sh
rg -n 'Data\\(contentsOf:|repository\\.(search|markUsed|setFavorite|delete|deleteAllNonFavorites)' \
  Sources/MacTools/Features/Clipboard/ClipboardPanelModel.swift
```

Expected: 无匹配。

- [ ] **Step 14: 提交 Task 2**

```sh
git add Package.swift \
  Sources/MacToolsCore/Paste/PasteActionService.swift \
  Tests/MacToolsCoreTests/PasteActionServiceTests.swift \
  Sources/MacTools/Application/AppEnvironmentWorkers.swift \
  Sources/MacTools/Features/Clipboard/ClipboardPanelModel.swift \
  Sources/MacTools/Features/Clipboard/ClipboardPasteFlow.swift \
  Sources/MacTools/Application/AppEnvironment.swift \
  Sources/MacTools/Application/RuntimeViews.swift \
  Tests/MacToolsTests/TestSupport.swift \
  Tests/MacToolsTests/ClipboardPanelModelTests.swift \
  Tests/MacToolsTests/ClipboardPasteFlowTests.swift
git commit -m "修复剪贴板面板主线程存储与图片处理" \
  -m "• 新增串行 ClipboardPanelWorker，后台执行查询、写入、GC 和图片准备
• 以 generation 阻止旧查询覆盖，并保持复制、权限和自动粘贴顺序
• 新增 MacTools 可执行层行为测试，覆盖失败副作用和收藏清理语义
• 验证：PasteActionService、ClipboardPanelModel、ClipboardPasteFlow、ClipboardRepository 聚焦测试通过"
```

---

### Task 3: P1 完整验证与风险状态更新

**Files:**

- Modify: `docs/superpowers/specs/2026-07-30-performance-risk-hardening-design.md`
- Modify when behavior changes require it: `docs/manual-verification.md`

**Interfaces:**

- Consumes: Task 1、Task 2 的两个独立提交和任务级评审结论。
- Produces: P1 完整验证记录；只有全部自动化门禁通过时才把 `PERF-P1-01`、`PERF-P1-02` 状态改为“已修复”。

- [ ] **Step 1: 运行严格并发构建**

Run:

```sh
swift build -Xswiftc -strict-concurrency=complete
```

Expected: 构建成功，不新增 Sendable、actor isolation 或 data race warning。

- [ ] **Step 2: 运行仓库已确认的完整 XCTest 隔离组合**

Run:

```sh
swift test --skip 'MacToolsCoreTests.SettingsNavigationTests/testToolbarHumanCadenceClickChangesEveryBoundPane'
swift test --filter 'MacToolsCoreTests.SettingsNavigationTests/testToolbarHumanCadenceClickChangesEveryBoundPane'
```

Expected: 第一条覆盖除真实窗口点击外的全部测试并 0 failure；第二条单测 0 failure。原始单进程 `swift test` 的已知 AppKit transform-animation 退出崩溃继续记录为测试基础设施风险，不伪装为通过。

- [ ] **Step 3: 构建、签名并启动打包应用**

Run:

```sh
scripts/rebuild_and_run_app.sh
```

Expected: `build/MacTools.app` 成功替换并启动；签名步骤成功。

- [ ] **Step 4: 执行打包应用人工功能验证**

在打包应用中逐项验证：

1. 文本、图片和文件分别执行“复制”，目标剪贴板内容正确；
2. 三种类型分别执行“复制并粘贴”，目标应用只收到一次 Command+V；
3. 拒绝事件发送权限时，内容已复制、面板保持可见并展示现有权限提示；
4. 删除普通图片后记录和关联 Payload 被移除；收藏图片保留；
5. 连续收藏、删除、清空时最终列表与重新打开面板后的数据库状态一致；
6. 面板明暗背景、尺寸、焦点、外部点击关闭和键盘导航无回归。

- [ ] **Step 5: 执行性能复测**

使用 Time Profiler 或等价采样，在至少 1,000 条记录且包含大 PNG 的面板中重复打开、滚动、切换分类、收藏和删除。验收：

- Main Thread 调用树不出现图片 `attributesOfItem`；
- Main Thread 调用树不出现 `ClipboardRepository.search/markUsed/setFavorite/delete/deleteAllNonFavorites`；
- Main Thread 调用树不出现图片 `Data(contentsOf:)`、PNG 规范化或 Payload GC；
- 面板交互期间主线程不存在由上述路径造成的超过 100 ms 阻塞。

- [ ] **Step 6: 更新风险文档并检查差异**

只有 Step 1–5 全部通过时，将设计文档中的两个 P1 状态改为“已修复”，并追加验证命令、测试数量、打包路径和性能采样结论。若用户可见权限或面板行为发生变化，同步最小更新 `docs/manual-verification.md`。

Run:

```sh
git diff --check
git diff --stat
```

Expected: 无空白错误，文档只记录事实和剩余风险。

- [ ] **Step 7: 提交并推送 P1 门禁结果**

```sh
git add docs/superpowers/specs/2026-07-30-performance-risk-hardening-design.md
git add docs/manual-verification.md
git commit -m "记录P1性能修复验证结果" \
  -m "• 更新图片预览和剪贴板面板风险状态
• 记录严格并发、完整 XCTest、打包人工验证和性能采样结果
• 验证：P1 完整门禁全部通过"
git push origin ai/performance-risk-hardening
```

如 `docs/manual-verification.md` 未发生变化，不得把它加入暂存区。P1 门禁通过并完成任务级规格/质量复审后，才创建 `2026-07-30-p2-performance-risk-hardening.md`。
