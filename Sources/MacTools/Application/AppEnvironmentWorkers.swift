// AppEnvironment 使用的后台工作器和一次性运行时协作者。
// 将目录准备、剪贴板轮询、存储维护和粘贴激活等待移出主 Actor。

import AppKit
import Foundation
import MacToolsCore

/// 同步目录准备完成后交回 MainActor 的不可变结果。
struct PreparedSyncFolder: Sendable {
    var rootURL: URL
    var bookmark: Data
    var descriptor: SyncProtocolDescriptor
    var isUbiquitous: Bool
}

/// 在独立 utility 串行队列执行 iCloud 目录创建、协议准备和 bookmark I/O。
final class SyncFolderPreparationWorker: @unchecked Sendable {
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let fileManager: FileManager
    private let queue = DispatchQueue(
        label: "com.mactools.sync-folder-preparation",
        qos: .utility
    )

    /// 注入设备级设置仓储和文件系统，并建立唯一的串行 I/O 队列。
    init(
        deviceOverrideRepository: DeviceOverrideRepository,
        fileManager: FileManager = .default
    ) {
        self.deviceOverrideRepository = deviceOverrideRepository
        self.fileManager = fileManager
    }

    /// 在安全作用域有效期间准备同步协议目录，并返回可在主 Actor 应用的不可变结果。
    func prepare(
        rootURL: URL,
        securityScopedURL: URL,
        initialCapacity: SyncStorageLimit
    ) async throws -> PreparedSyncFolder {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let didStartSecurityScope = securityScopedURL
                    .startAccessingSecurityScopedResource()
                defer {
                    if didStartSecurityScope {
                        securityScopedURL.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let standardizedRootURL = rootURL.standardizedFileURL
                    let descriptor = try DriveSyncStore(
                        rootURL: standardizedRootURL,
                        fileManager: self.fileManager
                    ).prepare(initialCapacity: initialCapacity)
                    let bookmark = try standardizedRootURL.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    continuation.resume(
                        returning: PreparedSyncFolder(
                            rootURL: standardizedRootURL,
                            bookmark: bookmark,
                            descriptor: descriptor,
                            isUbiquitous: self.fileManager.isUbiquitousItem(
                                at: standardizedRootURL
                            )
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 在同一 utility 队列持久化同步目录 bookmark 和展示路径，避免阻塞主 Actor。
    func persist(_ folder: PreparedSyncFolder) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.deviceOverrideRepository.setSyncFolder(
                        bookmark: folder.bookmark,
                        displayPath: folder.rootURL.path
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// 在独立高优先级串行队列每 100ms 读取轻量快照，不等待图片转码和数据库写入。
final class ClipboardSamplingWorker: @unchecked Sendable {
    private let sampler: ClipboardSnapshotSampler
    private let notificationCenter: NotificationCenter
    private let frontmostApplicationName: @Sendable () -> String?
    private let queue = DispatchQueue(
        label: "com.mactools.clipboard-sampling",
        qos: .userInitiated
    )
    private var timer: DispatchSourceTimer?
    private var pasteboardWriteObserver: NSObjectProtocol?
    private var onSnapshot: (@Sendable (ClipboardSnapshot) -> Void)?
    private var canSample: @Sendable () -> Bool = { true }
    private var admissionPaused = false
    private let captureLock = NSLock()
    private var captureScheduled = false

    init(
        sampler: ClipboardSnapshotSampler,
        notificationCenter: NotificationCenter = .default,
        frontmostApplicationName: @escaping @Sendable () -> String? = { NSWorkspace.shared.frontmostApplication?.localizedName }
    ) {
        self.sampler = sampler
        self.notificationCenter = notificationCenter
        self.frontmostApplicationName = frontmostApplicationName
    }

    /// 启动独立于主 RunLoop 的高频采样，并监听应用自身的剪贴板写入作为即时触发信号。
    func start(
        canSample: @escaping @Sendable () -> Bool = { true },
        onSnapshot: @escaping @Sendable (ClipboardSnapshot) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, self.onSnapshot == nil else { return }
            self.onSnapshot = onSnapshot
            self.canSample = canSample

            pasteboardWriteObserver = notificationCenter.addObserver(
                forName: .macToolsPasteboardDidWrite,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.captureSoon(sourceApp: "MacTools", onSnapshot: onSnapshot)
            }

            startTimerIfNeeded()
        }
    }

    /// 保留用户开关；恢复时跳过暂停期间的复制，下一次新复制才进入历史。
    func setAdmissionPaused(_ paused: Bool) {
        queue.async { [weak self] in
            guard let self, admissionPaused != paused else { return }
            admissionPaused = paused
            if paused {
                cancelTimer()
            } else {
                if sampler.isRecordingEnabled {
                    sampler.updateRecordingEnabled(false)
                    sampler.updateRecordingEnabled(true)
                }
                startTimerIfNeeded()
            }
        }
    }

    /// 等待已经提交的采样操作结束，不阻塞调用线程。
    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    /// 热更新录制开关；其余设置由持久化 Actor 在自己的串行边界内应用。
    func updateRecordingEnabled(_ isRecordingEnabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            sampler.updateRecordingEnabled(isRecordingEnabled)
            if isRecordingEnabled {
                startTimerIfNeeded()
            } else {
                cancelTimer()
            }
        }
    }

    /// 停止定时器和应用内写入观察者。
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            cancelTimer()
            onSnapshot = nil
            if let pasteboardWriteObserver {
                notificationCenter.removeObserver(pasteboardWriteObserver)
                self.pasteboardWriteObserver = nil
            }
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil, !admissionPaused, sampler.isRecordingEnabled, let onSnapshot else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.capture(
                sourceApp: self?.frontmostApplicationName(),
                onSnapshot: onSnapshot
            )
        }
        self.timer = timer
        timer.resume()
    }

    private func cancelTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func captureSoon(
        sourceApp: String?,
        onSnapshot: @escaping @Sendable (ClipboardSnapshot) -> Void
    ) {
        let shouldSchedule = captureLock.withLock {
            guard !captureScheduled else { return false }
            captureScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        queue.async { [weak self] in
            guard let self else { return }
            captureLock.withLock { self.captureScheduled = false }
            guard self.onSnapshot != nil else { return }
            capture(sourceApp: sourceApp, onSnapshot: onSnapshot)
        }
    }

    private func capture(
        sourceApp: @autoclosure () -> String?,
        onSnapshot: @escaping @Sendable (ClipboardSnapshot) -> Void
    ) {
        guard !admissionPaused, canSample() else { return }
        guard let snapshot = sampler.captureOnce(sourceApp: sourceApp()) else {
            return
        }
        onSnapshot(snapshot)
    }
}

/// 计入正在写入的队首，容量用尽时拒绝新快照，不删除已接受内容。
final class ClipboardSnapshotInbox: @unchecked Sendable {
    struct Status: Equatable, Sendable {
        var count = 0
        var bytes = 0
        var rejected = 0
        var capacityPaused = false
        var storagePaused = false
        var oversized = false
        var closed = false
        var isPaused: Bool { capacityPaused || storagePaused || closed }
        var warning: String? {
            if storagePaused { return "剪贴板历史写入失败，已暂停记录；待写内容仍保留，请检查存储后重试。" }
            if capacityPaused { return "剪贴板历史待写内容已达上限，已暂停记录；写入完成后自动恢复。" }
            if oversized { return "本次剪贴板内容超过记录容量，未加入历史。" }
            return nil
        }
    }
    private let lock = NSLock()
    private let maximumCount: Int
    private let maximumBytes: Int
    private var entries: [(ClipboardSnapshot, Int)] = []
    private var current = Status()
    private var retryRevision = 0
    private var onChange: (@Sendable () -> Void)?

    init(maximumCount: Int, maximumBytes: Int) {
        self.maximumCount = max(1, maximumCount)
        self.maximumBytes = max(1, maximumBytes)
    }
    var status: Status { lock.withLock { current } }
    var currentRetryRevision: Int { lock.withLock { retryRevision } }
    func requestRetry() {
        let callback = lock.withLock {
            retryRevision += 1
            current.oversized = false
            return onChange
        }
        callback?()
    }
    func setOnChange(_ callback: @escaping @Sendable () -> Void) {
        lock.withLock { onChange = callback }
    }
    @discardableResult
    func enqueue(_ snapshot: ClipboardSnapshot) -> Bool {
        // 数量同时限制对象开销；字节覆盖文本、图片、URL 和来源字符串。
        let bytes = max(1, (snapshot.payload.text?.utf8.count ?? 0)
            + (snapshot.payload.imageData?.count ?? 0)
            + snapshot.payload.fileURLs.reduce(0) { $0 + $1.absoluteString.utf8.count }
            + (snapshot.sourceApp?.utf8.count ?? 0))
        var callback: (@Sendable () -> Void)?
        let accepted = lock.withLock {
            guard !current.isPaused else { return false }
            if bytes > maximumBytes {
                current.rejected += 1
                current.oversized = true
                callback = onChange
                return false
            }
            guard entries.count < maximumCount, bytes <= maximumBytes - current.bytes else {
                current.rejected += 1
                current.capacityPaused = true
                callback = onChange
                return false
            }
            entries.append((snapshot, bytes))
            current.count = entries.count
            current.bytes += bytes
            if current.count == maximumCount || current.bytes == maximumBytes {
                current.capacityPaused = true
                callback = onChange
            }
            return true
        }
        callback?()
        return accepted
    }
    func first() -> ClipboardSnapshot? { lock.withLock { entries.first?.0 } }
    func completeFirst() {
        let callback = lock.withLock {
            let previous = current
            guard !entries.isEmpty else { return onChange }
            current.bytes -= entries.removeFirst().1
            current.count = entries.count
            current.storagePaused = false
            current.capacityPaused = current.count >= maximumCount || current.bytes >= maximumBytes
            return previous.isPaused != current.isPaused ? onChange : nil
        }
        callback?()
    }
    func markFailure() {
        let callback = lock.withLock {
            guard !current.storagePaused else { return Optional<@Sendable () -> Void>.none }
            current.storagePaused = true
            return onChange
        }
        callback?()
    }
    func close() {
        lock.withLock {
            current.closed = true
            onChange = nil
        }
    }
}

/// 串行落盘；流中只有一个唤醒信号，快照在同步入队处受数量和字节预算约束。
actor ClipboardPollingWorker {
    typealias Status = ClipboardSnapshotInbox.Status
    private let service: ClipboardService
    private let logger: Logger
    nonisolated private let inbox: ClipboardSnapshotInbox
    private let wakeups: AsyncStream<Void>
    nonisolated private let continuation: AsyncStream<Void>.Continuation
    private let retryDelay: @Sendable (Int) async throws -> Void
    private let maximumAttempts: Int
    private var consumptionTask: Task<Void, Never>?
    private var onRecorded: (@Sendable (ClipboardSnapshot) -> Void)?
    private var exhaustedRevision: Int?

    init(
        service: ClipboardService, logger: Logger,
        maximumCount: Int = 64, maximumBytes: Int = 64 * 1_024 * 1_024,
        maximumAttempts: Int = 3,
        retryDelay: @escaping @Sendable (Int) async throws -> Void = { attempt in
            try await Task.sleep(for: .milliseconds(500 * (1 << min(attempt - 1, 5))))
        }
    ) {
        let (wakeups, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.service = service
        self.logger = logger
        self.inbox = ClipboardSnapshotInbox(maximumCount: maximumCount, maximumBytes: maximumBytes)
        self.wakeups = wakeups
        self.continuation = continuation
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryDelay = retryDelay
    }
    nonisolated var status: Status { inbox.status }
    func start(
        onStatusChange: @escaping @Sendable () -> Void = {},
        onRecorded: @escaping @Sendable (ClipboardSnapshot) -> Void
    ) {
        inbox.setOnChange(onStatusChange)
        self.onRecorded = onRecorded
        guard consumptionTask == nil, !status.closed else { return }
        consumptionTask = Task { [weak self] in await self?.consumeSnapshots() }
        continuation.yield(())
    }
    @discardableResult
    nonisolated func enqueue(_ snapshot: ClipboardSnapshot) -> Bool {
        guard inbox.enqueue(snapshot) else { return false }
        continuation.yield(())
        return true
    }
    nonisolated func retryPending() {
        inbox.requestRetry()
        continuation.yield(())
    }
    func updateSettings(_ settings: AppSettings) { service.updateSettings(settings) }

    /// 正常停止会尝试排空已接受内容；快速取消保留失败队首并报告待写数量。
    func stop(cancelPendingRetries: Bool = false) async {
        inbox.close()
        continuation.finish()
        if cancelPendingRetries { consumptionTask?.cancel() }
        await consumptionTask?.value
        consumptionTask = nil
        onRecorded = nil
        if status.count > 0 { logger.error("clipboard stopped with pending snapshots: count=\(status.count)") }
    }
    private func consumeSnapshots() async {
        for await _ in wakeups {
            while !Task.isCancelled, let snapshot = inbox.first() {
                let retryRevision = inbox.currentRetryRevision
                guard exhaustedRevision != retryRevision else { break }
                guard await persistWithRetry(snapshot) else {
                    // 只耗尽开始本轮时的请求；写入期间的新重试仍由缓冲唤醒处理。
                    exhaustedRevision = retryRevision
                    break
                }
                exhaustedRevision = nil
                inbox.completeFirst()
            }
        }
    }
    private func persistWithRetry(_ snapshot: ClipboardSnapshot) async -> Bool {
        for attempt in 1...maximumAttempts {
            guard !Task.isCancelled else { return false }
            do {
                if try service.record(snapshot) { onRecorded?(snapshot) }
                return true
            } catch {
                inbox.markFailure()
                logger.error("clipboard persistence failed: attempt=\(attempt), error=\(String(reflecting: type(of: error)))")
                // 解码和参数错误不会因等待而恢复，保留队首等待明确重试。
                if !Self.shouldRetry(error) || attempt == maximumAttempts { return false }
                do { try await retryDelay(attempt) } catch { return false }
            }
        }
        return false
    }
    private static func shouldRetry(_ error: Error) -> Bool {
        if error is DecodingError { return false }
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return ![CocoaError.fileWriteOutOfSpace.rawValue, CocoaError.fileWriteNoPermission.rawValue,
                     CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteInvalidFileName.rawValue].contains(error.code)
        }
        if error.domain == NSPOSIXErrorDomain { return ![Int(ENOSPC), Int(EACCES), Int(EROFS)].contains(error.code) }
        return true
    }
}

/// 合并后台通知，主 Actor 至多保留一个待执行任务。
final class MainActorChangeNotification: @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled = false
    private let action: @MainActor @Sendable () -> Void
    init(action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    func signal() {
        guard lock.withLock({
            if scheduled { return false }
            scheduled = true
            return true
        }) else { return }
        Task { @MainActor [self] in
            lock.withLock { scheduled = false }
            action()
        }
    }
}

/// 串行管理 `AppMaintenanceWorker` 在应用运行时与 AppKit 集成中的可变状态和异步操作。
actor AppMaintenanceWorker {
    private let repository: ClipboardRepository
    private let payloadStore: PayloadStore
    private let usesPersistentDatabase: Bool
    private let logger: Logger
    private var hasRun = false

    /// 创建 `AppMaintenanceWorker`，保存传入依赖并建立初始状态。
    init(
        repository: ClipboardRepository,
        payloadStore: PayloadStore,
        usesPersistentDatabase: Bool,
        logger: Logger
    ) {
        self.repository = repository
        self.payloadStore = payloadStore
        self.usesPersistentDatabase = usesPersistentDatabase
        self.logger = logger
    }

    /// 每次进程生命周期只执行一次临时文件、载荷引用和本地保留标记清理。
    func run(now: Date = Date()) {
        guard !hasRun else { return }
        hasRun = true

        do {
            try payloadStore.removeStagingFiles(
                olderThan: now.addingTimeInterval(-24 * 60 * 60)
            )
        } catch {
            logger.error(
                "payload staging cleanup failed: \(String(reflecting: type(of: error)))"
            )
        }
        guard usesPersistentDatabase else { return }

        do {
            try repository.reconcilePayloadStorage()
        } catch {
            logger.error(
                "payload storage reconciliation failed: \(String(reflecting: type(of: error)))"
            )
        }
        do {
            let removedEvictionCount = try repository.cleanupOrphanedLocalEvictions()
            if removedEvictionCount > 0 {
                logger.info(
                    "removed orphaned local retention markers: count=\(removedEvictionCount)"
                )
            }
        } catch {
            logger.error(
                "local retention marker cleanup failed: \(String(reflecting: type(of: error)))"
            )
        }
        enforceCacheLimit()
    }

    /// 读取仓储的最新内存预算，在后台裁剪普通项并回收无引用载荷。
    func enforceCacheLimit() {
        do {
            try repository.enforceCacheLimit()
        } catch {
            logger.error("clipboard cache limit enforcement failed: \(String(reflecting: type(of: error)))")
        }
    }
}

/// 激活期间保留可取消的延迟任务，发送事件前重新检查原进程身份与焦点。
@MainActor
final class PasteActivationAttempt {
    private let targetApplication: NSRunningApplication
    private let targetProcessIdentifier: pid_t
    private let notificationCenter: NotificationCenter
    private let logger: Logger
    private let paste: () -> Void
    private let onFinish: (PasteActivationAttempt) -> Void
    private let frontmostApplication: () -> NSRunningApplication?
    private let delay: @Sendable (Duration) async throws -> Void
    private var observer: NSObjectProtocol?
    private var notificationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isFinished = false

    init(
        targetApplication: NSRunningApplication,
        notificationCenter: NotificationCenter,
        logger: Logger,
        paste: @escaping () -> Void,
        onFinish: @escaping (PasteActivationAttempt) -> Void,
        frontmostApplication: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
        delay: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.targetApplication = targetApplication
        self.targetProcessIdentifier = targetApplication.processIdentifier
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.paste = paste
        self.onFinish = onFinish
        self.frontmostApplication = frontmostApplication
        self.delay = delay
    }

    deinit {
        notificationTask?.cancel()
        timeoutTask?.cancel()
        if let observer { notificationCenter.removeObserver(observer) }
    }

    func start() {
        guard !isFinished, timeoutTask == nil else { return }
        guard targetIsAlive else { finish(); return }
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      activated.isEqual(self.targetApplication), self.targetIsAlive, !self.isFinished else { return }
                self.notificationTask?.cancel()
                let delay = self.delay
                self.notificationTask = Task { @MainActor [weak self] in
                    do { try await delay(.milliseconds(80)) } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.pasteOnce()
                }
            }
        }
        targetApplication.unhide()
        guard targetApplication.activate(options: [.activateAllWindows]) else {
            logger.error("paste target activation failed; automatic paste cancelled")
            finish()
            return
        }
        let delay = self.delay
        timeoutTask = Task { @MainActor [weak self] in
            do { try await delay(.milliseconds(800)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.pasteOnce()
        }
    }

    func cancel() { finish() }
    private var targetIsAlive: Bool {
        targetProcessIdentifier > 0 && !targetApplication.isTerminated
            && targetApplication.processIdentifier == targetProcessIdentifier
    }
    private func pasteOnce() {
        guard !isFinished else { return }
        guard targetIsAlive, let frontmost = frontmostApplication(),
              frontmost.isEqual(targetApplication), frontmost.isActive else {
            logger.error("paste target lost focus or terminated; automatic paste cancelled")
            finish()
            return
        }
        finish(sendPaste: true)
    }
    private func finish(sendPaste: Bool = false) {
        guard !isFinished else { return }
        isFinished = true
        notificationTask?.cancel()
        timeoutTask?.cancel()
        notificationTask = nil
        timeoutTask = nil
        if let observer { notificationCenter.removeObserver(observer) }
        observer = nil
        if sendPaste { paste() }
        onFinish(self)
    }
}
