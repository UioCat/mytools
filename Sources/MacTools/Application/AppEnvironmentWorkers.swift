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

/// 串行管理 `ClipboardPollingWorker` 在应用运行时与 AppKit 集成中的可变状态和异步操作。
actor ClipboardPollingWorker {
    private let service: ClipboardService

    /// 创建 `ClipboardPollingWorker`，保存传入依赖并建立初始状态。
    init(service: ClipboardService) {
        self.service = service
    }

    /// 安排或刷新 `pollOnce` 对应的应用运行时与 AppKit 集成工作。
    func pollOnce(sourceApp: String?) throws -> Bool {
        try service.pollOnce(sourceApp: sourceApp)
    }

    /// 应用 `updateSettings` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func updateSettings(_ settings: AppSettings) {
        service.updateSettings(settings)
    }
}

/// 剪贴板面板访问存储和准备载荷时使用的异步边界。
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

/// 串行执行剪贴板面板的仓储访问、载荷清理和图片准备。
actor ClipboardPanelWorker: ClipboardPanelWorking {
    private let repository: ClipboardRepository

    init(repository: ClipboardRepository) {
        self.repository = repository
    }

    func load(limit: Int) throws -> [ClipboardItem] {
        try repository.search("", limit: limit)
    }

    func markUsedAndLoad(
        id: UUID,
        at date: Date,
        limit: Int
    ) throws -> [ClipboardItem] {
        try repository.markUsed(id: id, at: date)
        return try repository.search("", limit: limit)
    }

    func setFavoriteAndLoad(
        id: UUID,
        isFavorite: Bool,
        historyLimit: Int,
        limit: Int
    ) throws -> [ClipboardItem] {
        try repository.setFavorite(
            id: id,
            isFavorite: isFavorite,
            historyLimit: historyLimit
        )
        return try repository.search("", limit: limit)
    }

    func deleteAndLoad(
        id: UUID,
        limit: Int
    ) throws -> [ClipboardItem] {
        try repository.delete(id: id)
        return try repository.search("", limit: limit)
    }

    func clearNonFavoritesAndLoad(
        limit: Int
    ) throws -> [ClipboardItem] {
        try repository.deleteAllNonFavorites()
        return try repository.search("", limit: limit)
    }

    func prepareContent(
        for item: ClipboardItem
    ) throws -> PreparedPasteboardContent {
        try PasteActionService.prepareContent(for: item)
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
    private let targetApplication: NSRunningApplication?
    private let notificationCenter: NotificationCenter
    private let logger: Logger
    private let fallbackWait: () async -> Void
    private let paste: () -> Void
    private let onFinish: (PasteActivationAttempt) -> Void
    private var observer: NSObjectProtocol?
    private var fallbackTask: Task<Void, Never>?
    private var didPaste = false

    /// 创建 `PasteActivationAttempt`，保存传入依赖并建立初始状态。
    init(
        targetApplication: NSRunningApplication?,
        notificationCenter: NotificationCenter,
        logger: Logger,
        fallbackWait: @escaping () async -> Void = {
            try? await Task.sleep(for: .milliseconds(250))
        },
        paste: @escaping () -> Void,
        onFinish: @escaping (PasteActivationAttempt) -> Void
    ) {
        self.targetApplication = targetApplication
        self.notificationCenter = notificationCenter
        self.logger = logger
        self.fallbackWait = fallbackWait
        self.paste = paste
        self.onFinish = onFinish
    }

    /// 激活原前台应用，并以激活通知优先、超时兜底的方式仅发送一次粘贴。
    @discardableResult
    func start() -> Task<Void, Never>? {
        guard let targetApplication else {
            logger.error("paste target missing; sending paste after fallback delay")
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await fallbackWait()
                guard !Task.isCancelled else { return }
                pasteOnce(reason: "missing target fallback")
            }
            fallbackTask = task
            return task
        }

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
        return nil
    }

    /// 取消尚未发送的粘贴，并移除应用激活观察者。
    func cancel() {
        guard !didPaste else { return }
        didPaste = true
        fallbackTask?.cancel()
        fallbackTask = nil
        removeObserver()
        onFinish(self)
    }

    /// 原子地标记本次尝试已完成，确保通知路径和超时路径不会重复粘贴。
    private func pasteOnce(reason: String) {
        guard !didPaste else { return }
        didPaste = true
        fallbackTask = nil
        removeObserver()

        let targetName = targetApplication?.localizedName ?? "missing target"
        logger.info("sending paste to \(targetName) via \(reason)")
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
