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
    private let queue = DispatchQueue(
        label: "com.mactools.clipboard-sampling",
        qos: .userInitiated
    )
    private var timer: DispatchSourceTimer?
    private var pasteboardWriteObserver: NSObjectProtocol?

    init(
        sampler: ClipboardSnapshotSampler,
        notificationCenter: NotificationCenter = .default
    ) {
        self.sampler = sampler
        self.notificationCenter = notificationCenter
    }

    /// 启动独立于主 RunLoop 的高频采样，并监听应用自身的剪贴板写入作为即时触发信号。
    func start(onSnapshot: @escaping @Sendable (ClipboardSnapshot) -> Void) {
        queue.async { [weak self] in
            guard let self, timer == nil else { return }

            pasteboardWriteObserver = notificationCenter.addObserver(
                forName: .macToolsPasteboardDidWrite,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.captureSoon(sourceApp: "MacTools", onSnapshot: onSnapshot)
            }

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(),
                repeating: .milliseconds(100),
                leeway: .milliseconds(10)
            )
            timer.setEventHandler { [weak self] in
                let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
                self?.capture(sourceApp: sourceApp, onSnapshot: onSnapshot)
            }
            self.timer = timer
            timer.resume()
        }
    }

    /// 热更新录制开关；其余设置由持久化 Actor 在自己的串行边界内应用。
    func updateRecordingEnabled(_ isRecordingEnabled: Bool) {
        queue.async { [weak self] in
            self?.sampler.updateRecordingEnabled(isRecordingEnabled)
        }
    }

    /// 停止定时器和应用内写入观察者。
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            if let pasteboardWriteObserver {
                notificationCenter.removeObserver(pasteboardWriteObserver)
                self.pasteboardWriteObserver = nil
            }
        }
    }

    private func captureSoon(
        sourceApp: String?,
        onSnapshot: @escaping @Sendable (ClipboardSnapshot) -> Void
    ) {
        queue.async { [weak self] in
            self?.capture(sourceApp: sourceApp, onSnapshot: onSnapshot)
        }
    }

    private func capture(
        sourceApp: String?,
        onSnapshot: @escaping @Sendable (ClipboardSnapshot) -> Void
    ) {
        guard let snapshot = sampler.captureOnce(sourceApp: sourceApp) else {
            return
        }
        onSnapshot(snapshot)
    }
}

/// 串行消费不可变剪贴板快照；持久化失败时保留队首并延迟重试。
actor ClipboardPollingWorker {
    private let service: ClipboardService
    private let logger: Logger
    private let snapshots: AsyncStream<ClipboardSnapshot>
    nonisolated private let snapshotContinuation: AsyncStream<ClipboardSnapshot>.Continuation
    private var consumptionTask: Task<Void, Never>?
    private var onRecorded: (@Sendable (ClipboardSnapshot) -> Void)?

    /// 创建 `ClipboardPollingWorker`，保存传入依赖并建立初始状态。
    init(service: ClipboardService, logger: Logger) {
        let (snapshots, snapshotContinuation) = AsyncStream<ClipboardSnapshot>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.service = service
        self.logger = logger
        self.snapshots = snapshots
        self.snapshotContinuation = snapshotContinuation
    }

    /// 配置成功持久化通知并启动唯一消费任务，保证快照严格按采样顺序落盘。
    func start(onRecorded: @escaping @Sendable (ClipboardSnapshot) -> Void) {
        self.onRecorded = onRecorded
        guard consumptionTask == nil else { return }
        consumptionTask = Task { [weak self] in
            await self?.consumeSnapshots()
        }
    }

    /// `AsyncStream.Continuation` 可跨线程同步入队，采样队列无需等待 Actor 或持久化。
    nonisolated func enqueue(_ snapshot: ClipboardSnapshot) {
        snapshotContinuation.yield(snapshot)
    }

    /// 应用 `updateSettings` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func updateSettings(_ settings: AppSettings) {
        service.updateSettings(settings)
    }

    /// 结束快照流并取消当前消费或重试等待。
    func stop() {
        snapshotContinuation.finish()
        consumptionTask?.cancel()
        consumptionTask = nil
    }

    private func consumeSnapshots() async {
        for await snapshot in snapshots {
            guard !Task.isCancelled else { return }
            if snapshot.skippedChangeCount > 0 {
                logger.error(
                    "clipboard sampler observed skipped changes: count="
                        + "\(snapshot.skippedChangeCount), changeCount=\(snapshot.changeCount)"
                )
            }
            await persistWithRetry(snapshot)
        }
    }

    private func persistWithRetry(_ snapshot: ClipboardSnapshot) async {
        while !Task.isCancelled {
            do {
                let recorded = try service.record(snapshot)
                if recorded {
                    onRecorded?(snapshot)
                }
                return
            } catch {
                logger.error(
                    "clipboard snapshot persistence failed; retrying: changeCount="
                        + "\(snapshot.changeCount), error="
                        + String(reflecting: type(of: error))
                )
                try? await Task.sleep(for: .milliseconds(500))
            }
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
    }
}

/// 管理 `PasteActivationAttempt` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class PasteActivationAttempt {
    private let targetApplication: NSRunningApplication
    private let notificationCenter: NotificationCenter
    private let logger: Logger
    private let paste: () -> Void
    private let onFinish: (PasteActivationAttempt) -> Void
    private var observer: NSObjectProtocol?
    private var didPaste = false

    /// 创建 `PasteActivationAttempt`，保存传入依赖并建立初始状态。
    init(
        targetApplication: NSRunningApplication,
        notificationCenter: NotificationCenter,
        logger: Logger,
        paste: @escaping () -> Void,
        onFinish: @escaping (PasteActivationAttempt) -> Void
    ) {
        self.targetApplication = targetApplication
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.paste = paste
        self.onFinish = onFinish
    }

    /// 激活原前台应用，并以激活通知优先、超时兜底的方式仅发送一次粘贴。
    func start() {
        let targetProcessIdentifier = targetApplication.processIdentifier
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedProcessIdentifier = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.processIdentifier
            guard activatedProcessIdentifier == targetProcessIdentifier else { return }

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                self?.pasteOnce(reason: "activation notification")
            }
        }

        targetApplication.unhide()
        targetApplication.activate(options: [.activateAllWindows])

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.pasteOnce(reason: "activation timeout fallback")
        }
    }

    /// 取消尚未发送的粘贴，并移除应用激活观察者。
    func cancel() {
        guard !didPaste else { return }
        didPaste = true
        removeObserver()
        onFinish(self)
    }

    /// 原子地标记本次尝试已完成，确保通知路径和超时路径不会重复粘贴。
    private func pasteOnce(reason: String) {
        guard !didPaste else { return }
        didPaste = true
        removeObserver()

        logger.info(
            "sending paste to \(targetApplication.localizedName ?? "unknown") via \(reason)"
        )
        paste()
        onFinish(self)
    }

    /// 移除 `removeObserver` 指定的应用运行时与 AppKit 集成数据，并维护关联状态。
    private func removeObserver() {
        guard let observer else { return }
        notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
