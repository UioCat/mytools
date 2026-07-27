// `AppEnvironment` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import AppKit
import Foundation
import MacToolsCore

/// 描述 `AppEnvironmentError` 在应用运行时与 AppKit 集成中可取的状态、选项或错误。
private enum AppEnvironmentError: Error {
    case unavailable
    case syncFolderUnavailable
}

/// 管理 `AppEnvironment` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
@MainActor
final class AppEnvironment {
    let logger = Logger()
    private let preferenceRepository: PreferenceRepository
    private let deviceOverrideRepository: DeviceOverrideRepository
    private let encryptedCredentialStore: EncryptedCredentialStore
    let credentialAccess: CredentialAccessCoordinator
    let translationCredentialModel: TranslationCredentialViewModel
    var settings: AppSettings
    private let repository: ClipboardRepository
    private let clipboardPollingWorker: ClipboardPollingWorker
    private let maintenanceWorker: AppMaintenanceWorker
    private let syncFolderPreparationWorker: SyncFolderPreparationWorker
    private let payloadStore: PayloadStore
    private let syncLocalRepository: SyncLocalRepository
    var syncFolderURL: URL?
    private let defaultClipboardCacheDirectory: URL
    private let pasteActionService: PasteActionService
    private let permissionService = PermissionService()
    private let fileActionService = FileActionService(workspace: SystemWorkspaceOpening())
    private let finderCurrentFolderResolver: any FinderCurrentFolderResolving = SystemFinderCurrentFolderResolver()
    private let finderFolderResolutionCoordinator = FinderFolderResolutionCoordinator()
    private let mainPanelRouter = MainPanelRouter()
    private let mainPanelDismissHandler = PanelDismissHandler()
    private let syncModel = SyncViewModel()
    lazy var syncCoordinator = ICloudDriveSyncCoordinator(
        localRepository: syncLocalRepository,
        deviceOverrideRepository: deviceOverrideRepository,
        payloadStore: payloadStore,
        encryptedCredentialStore: encryptedCredentialStore,
        historyLimit: settings.clipboard.maxHistoryCount,
        clipboardScope: settings.sync.clipboardScope,
        storageLimit: settings.sync.storageLimit,
        rootURL: syncFolderURL,
        statusHandler: { [weak self] status in
            Task { @MainActor in
                self?.syncModel.status = status
            }
        },
        remoteSettingsHandler: { [weak self] remoteSettings in
            Task { @MainActor in
                self?.applyRemoteSettings(remoteSettings)
            }
        },
        devicesHandler: { [weak self] devices in
            Task { @MainActor in
                self?.syncModel.devices = devices
            }
        },
        credentialStateHandler: { [weak self] state in
            Task { @MainActor in
                self?.handleCredentialCloudState(state)
            }
        }
    )
    private lazy var translationSpeechController = TranslationSpeechController(
        engine: SystemTranslationSpeechEngine()
    )
    private lazy var screenCaptureCoordinator = ScreenCaptureCoordinator(
        permissionService: permissionService,
        logger: logger,
        settingsProvider: { [weak self] in
            self?.settings.screenCapture ?? .defaults
        },
        onSettingsChange: { [weak self] screenCaptureSettings in
            self?.saveScreenCaptureSettings(screenCaptureSettings) ?? false
        }
    )
    private var clipboardTimer: Timer?
    private var superRightClickMonitor: SuperRightClickMonitor?
    private var appBeforePanel: NSRunningApplication?
    private var pasteActivationAttempt: PasteActivationAttempt?
    var credentialLoadGeneration = 0
    var credentialLoadFinished = false
    var credentialLegacyLoadStarted = false
    var legacySettingsURL: URL?
    private var syncFolderSelectionGeneration = 0

    private lazy var clipboardModel = ClipboardPanelModel(
        repository: repository,
        pasteActionService: pasteActionService,
        logger: logger,
        historyLimit: { [weak self] in
            self?.settings.clipboard.maxHistoryCount
                ?? AppSettings.defaults.clipboard.maxHistoryCount
        },
        onLocalChange: { [weak self] in self?.scheduleSync() }
    )

    lazy var mainPanel = MainPanelController(
        initialSize: NSSize(
            width: LiquidGlassWindowPanelFrame.mainWorkspace.idealWidth,
            height: LiquidGlassWindowPanelFrame.mainWorkspace.idealHeight
        ),
        minimumSize: NSSize(
            width: LiquidGlassWindowPanelFrame.mainWorkspace.minWidth,
            height: LiquidGlassWindowPanelFrame.mainWorkspace.minHeight
        ),
        rootView: RuntimeMainWorkspaceView(
            router: mainPanelRouter,
            model: clipboardModel,
            settings: settings,
            syncModel: syncModel,
            translationCredentialModel: translationCredentialModel,
            speechController: translationSpeechController,
            permissionService: permissionService,
            defaultClipboardCacheDirectory: defaultClipboardCacheDirectory,
            onSaveClipboardSettings: { [weak self] clipboardSettings in
                guard let self else {
                    throw AppEnvironmentError.unavailable
                }
                return try self.saveClipboardSettings(clipboardSettings)
            },
            onSaveTranslationSettings: { [weak self] translationSettings, apiKeyWasEdited in
                guard let self else {
                    throw AppEnvironmentError.unavailable
                }
                return try await self.saveTranslationSettings(
                    translationSettings,
                    apiKeyWasEdited: apiKeyWasEdited
                )
            },
            onSaveSuperRightClickSettings: { [weak self] superRightClickSettings in
                guard let self else {
                    throw AppEnvironmentError.unavailable
                }
                return try self.saveSuperRightClickSettings(superRightClickSettings)
            },
            onSaveWindowLayoutSettings: { [weak self] windowLayoutSettings in
                guard let self else {
                    throw AppEnvironmentError.unavailable
                }
                return try self.saveWindowLayoutSettings(windowLayoutSettings)
            },
            onSaveAppearanceMode: { [weak self] appearanceMode in
                guard let self else {
                    throw AppEnvironmentError.unavailable
                }
                return try self.saveAppearanceMode(appearanceMode)
            },
            onSaveSyncSettings: { [weak self] syncSettings in
                guard let self else {
                    throw AppEnvironmentError.unavailable
                }
                return try self.saveSyncSettings(syncSettings)
            },
            onSyncNow: { [weak self] in
                self?.syncCoordinator.syncNow()
            },
            onDeleteCloudData: { [weak self] in
                self?.syncCoordinator.resetSyncData()
            },
            onOpenClipboardStorageFolder: { [weak self] in
                self?.openClipboardStorageFolder()
            },
            onSelectSyncFolder: { [weak self] in self?.selectSyncFolder() },
            onOpenSyncFolder: { [weak self] in self?.openSyncFolder() },
            onRemoveSyncDevice: { [weak self] deviceID in
                self?.syncCoordinator.removeDevice(deviceID)
            },
            onCopy: { [weak self] item in
                self?.copyFromPanel(item)
            },
            onCopyAndPaste: { [weak self] item in
                self?.pasteFromPanel(item)
            },
            onDismiss: { [mainPanelDismissHandler] in
                mainPanelDismissHandler.dismiss()
            }
        )
    )

    private lazy var windowLayoutService = SystemWindowLayoutService(logger: logger)

    private lazy var contextPanel = ContextPanelController(
        fileActionService: fileActionService,
        pasteboard: SystemWritablePasteboard(),
        windowLayoutService: windowLayoutService,
        windowLayoutButtons: { [weak self] in
            self?.settings.windowLayout.visibleButtons ?? []
        },
        speechController: translationSpeechController,
        logger: logger
    )
    var onSettingsChanged: (AppSettings) -> Void = { _ in }
    /// 创建 `AppEnvironment`，保存传入依赖并建立初始状态。
    init() {
        let supportDirectory = Self.applicationSupportDirectory()
        let storePaths = MacToolsStorePaths(supportDirectory: supportDirectory)
        let legacySettingsStore = SettingsStore(fileURL: storePaths.legacySettingsURL)
        let legacySettings = (try? legacySettingsStore.load()) ?? .defaults
        let encryptedCredentialStore = EncryptedCredentialStore(
            envelopeURL: storePaths.bailianCredentialURL,
            migrationMarkerURL: storePaths.credentialMigrationMarkerURL
        )
        let legacyCredentialReader = LegacyKeychainCredentialReader()

        let database: ClipboardDatabase
        let usesPersistentDatabase: Bool
        do {
            let bootstrap = try UnifiedStoreBootstrapper.prepare(
                paths: storePaths,
                legacySettings: legacySettings
            )
            database = try ClipboardDatabase.at(storePaths.databaseURL)
            usesPersistentDatabase = true
            logger.info(
                "unified store ready: processed=\(bootstrap.migrationReport.importedClipboardItems), "
                    + "missingImages=\(bootstrap.migrationReport.skippedMissingImages), "
                    + "invalid=\(bootstrap.migrationReport.skippedInvalidRecords), "
                    + "cutover=\(bootstrap.didCutOver)"
            )
        } catch {
            logger.error(
                "unified store bootstrap failed; using isolated in-memory store: "
                    + "\(String(reflecting: type(of: error)))"
            )
            database = try! ClipboardDatabase.inMemory()
            usesPersistentDatabase = false
        }

        let preferenceRepository = PreferenceRepository(database: database)
        let deviceOverrideRepository = DeviceOverrideRepository(database: database)
        var loadedSettings = (try? preferenceRepository.load()) ?? legacySettings
        loadedSettings.sync.isEnabled = (try? deviceOverrideRepository.isSyncEnabled()) ?? false
        let syncFolderURL = Self.resolveSyncFolderBookmark(
            (try? deviceOverrideRepository.syncFolderBookmark()) ?? nil
        )
        let legacyCredential = legacySettings.translation.apiKey
        loadedSettings.translation.apiKey = legacyCredential
        if usesPersistentDatabase, (try? preferenceRepository.load()) == nil {
            do {
                try preferenceRepository.save(loadedSettings, enqueuesSyncChange: false)
            } catch {
                logger.error("preference seed failed: \(String(reflecting: type(of: error)))")
            }
        }
        self.preferenceRepository = preferenceRepository
        self.deviceOverrideRepository = deviceOverrideRepository
        self.syncFolderPreparationWorker = SyncFolderPreparationWorker(
            deviceOverrideRepository: deviceOverrideRepository
        )
        self.encryptedCredentialStore = encryptedCredentialStore
        self.credentialAccess = CredentialAccessCoordinator(
            store: encryptedCredentialStore,
            legacyReader: legacyCredentialReader,
            deviceID: (try? deviceOverrideRepository.deviceID().uuidString)
                ?? UUID().uuidString
        )
        self.translationCredentialModel = TranslationCredentialViewModel(apiKey: legacyCredential)
        self.settings = loadedSettings
        self.syncFolderURL = syncFolderURL
        self.legacySettingsURL = usesPersistentDatabase ? storePaths.legacySettingsURL : nil

        let payloadDirectory = storePaths.runtimePayloadsDirectory(
            persistentStoreAvailable: usesPersistentDatabase
        )
        let payloadStore = PayloadStore(rootDirectory: payloadDirectory)
        let repository = ClipboardRepository(database: database, payloadStore: payloadStore)
        self.repository = repository
        self.payloadStore = payloadStore
        self.maintenanceWorker = AppMaintenanceWorker(
            repository: repository,
            payloadStore: payloadStore,
            usesPersistentDatabase: usesPersistentDatabase,
            logger: logger
        )
        self.syncLocalRepository = SyncLocalRepository(
            database: database,
            clipboardRepository: repository,
            preferenceRepository: preferenceRepository
        )
        self.pasteActionService = PasteActionService(
            pasteboard: SystemWritablePasteboard(),
            eventSender: SystemPasteEventSender()
        )
        let defaultClipboardCacheDirectory = payloadDirectory
        self.defaultClipboardCacheDirectory = defaultClipboardCacheDirectory
        self.clipboardPollingWorker = ClipboardPollingWorker(service: ClipboardService(
            pasteboard: SystemPasteboardClient(),
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: loadedSettings,
            payloadStore: payloadStore
        ))
        self.syncModel.folderPath = try? deviceOverrideRepository.syncFolderDisplayPath()
        self.syncModel.folderIsUbiquitous = syncFolderURL.map {
            FileManager.default.isUbiquitousItem(at: $0)
        }
        if syncFolderURL == nil {
            syncModel.status = syncModel.folderPath == nil ? .unconfigured : .folderUnavailable
        } else if !loadedSettings.sync.isEnabled {
            syncModel.status = .off
        }
    }

    /// 启动轮询、全局右键、同步、凭据加载和一次性后台维护任务。
    func start() {
        mainPanelDismissHandler.onDismiss = { [weak self] in
            self?.mainPanel.hide()
        }
        startClipboardPolling()
        startSuperRightClickMonitor()
        syncCoordinator.setRootURL(syncFolderURL)
        syncCoordinator.setEnabled(settings.sync.isEnabled, syncImmediately: false)
        loadTranslationCredentialIfNeeded()
        let maintenanceWorker = maintenanceWorker
        Task {
            await maintenanceWorker.run()
        }
    }

    /// 展示 `openMainPanel` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func openMainPanel() {
        captureFrontmostApplicationBeforePanel()
        mainPanelRouter.open(.settings)
        mainPanel.show()
    }

    /// 展示 `openClipboard` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func openClipboard() {
        captureFrontmostApplicationBeforePanel()
        clipboardModel.prepareForPresentation()
        mainPanelRouter.open(.clipboard)
        mainPanel.show()
    }

    /// 展示 `openTranslation` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func openTranslation() {
        captureFrontmostApplicationBeforePanel()
        mainPanelRouter.open(.translation)
        mainPanel.show()
    }

    /// 展示 `openSettings` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func openSettings() {
        openMainPanel()
    }

    /// 展示 `openSettingsForUIVerification` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func openSettingsForUIVerification() {
        var previewSettings = settings
        previewSettings.sync = SyncSettings(
            isEnabled: true,
            clipboardScope: .allHistory,
            storageLimit: .megabytes512
        )
        syncModel.folderPath = "/Users/example/iCloud Drive/MacTools Sync"
        syncModel.folderIsUbiquitous = true
        syncModel.status = .synced(
            lastSyncAt: Date(),
            usage: SyncStorageUsage(
                usedBytes: 187 * 1_024 * 1_024,
                capacityBytes: SyncStorageLimit.megabytes512.byteLimit,
                ordinaryHistoryCount: 328,
                imageBytes: 180 * 1_024 * 1_024,
                textBytes: 2 * 1_024 * 1_024,
                metadataBytes: 5 * 1_024 * 1_024
            )
        )
        syncModel.devices = [
            SyncDeviceSummary(
                id: "verification-current",
                name: "MacBook Pro",
                isCurrentDevice: true,
                lastUpdatedAt: Date()
            ),
            SyncDeviceSummary(
                id: "verification-peer",
                name: "Mac Studio",
                isCurrentDevice: false,
                lastUpdatedAt: Date().addingTimeInterval(-3_600)
            )
        ]
        syncModel.remoteSettings = previewSettings
        openSettings()
        mainPanel.resize(to: NSSize(width: 980, height: 900))
    }

    /// 展示 `openScreenCapture` 对应的应用运行时与 AppKit 集成界面或系统位置。
    func openScreenCapture() {
        screenCaptureCoordinator.start()
    }

    /// 应用 `applyWindowLayout` 接收的新值，并更新相关应用运行时与 AppKit 集成状态。
    func applyWindowLayout(_ mode: WindowLayoutMode) {
        do {
            try windowLayoutService.apply(button: WindowLayoutButton(mode: mode))
        } catch {
            logger.error("window layout hotkey failed: \(error)")
        }
    }

    /// 保存翻译设置；API Key 被编辑时先写加密凭据，再保存不含明文密钥的偏好。
    private func saveTranslationSettings(
        _ translationSettings: TranslationSettings,
        apiKeyWasEdited: Bool
    ) async throws -> AppSettings {
        var updated = settings
        var normalizedTranslationSettings = translationSettings
        normalizedTranslationSettings.providerID = TranslationSettings.defaultProviderID
        normalizedTranslationSettings = normalizedTranslationSettings.resolvingAPIKey(
            currentAPIKey: settings.translation.apiKey,
            wasEdited: apiKeyWasEdited
        )
        updated.translation = normalizedTranslationSettings

        let apiKey = normalizedTranslationSettings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKeyWasEdited {
            // 凭据存储与偏好存储不是同一事务：后续偏好写入失败时，加密凭据可能已更新。
            credentialLoadGeneration += 1
            credentialLoadFinished = true
            do {
                try await credentialAccess.save(apiKey, for: .bailianAPIKey)
            } catch {
                translationCredentialModel.isUnavailable = true
                throw error
            }
            if let legacySettingsURL {
                redactLegacyCredential(at: legacySettingsURL)
            }
        }
        try preferenceRepository.save(updated)
        settings = updated
        if apiKeyWasEdited {
            translationCredentialModel.apiKey = apiKey
            translationCredentialModel.isUnavailable = false
        }
        onSettingsChanged(updated)
        startSuperRightClickMonitor()
        scheduleSync()

        return updated
    }

    /// 保存 `saveClipboardSettings` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    private func saveClipboardSettings(_ clipboardSettings: ClipboardSettings) throws -> AppSettings {
        var updated = settings
        updated.clipboard = clipboardSettings

        try preferenceRepository.save(updated)
        settings = updated
        onSettingsChanged(updated)
        Task { await clipboardPollingWorker.updateSettings(updated) }
        clipboardModel.refresh()
        syncCoordinator.updateConfiguration(
            historyLimit: updated.clipboard.maxHistoryCount,
            clipboardScope: updated.sync.clipboardScope,
            storageLimit: updated.sync.storageLimit
        )
        scheduleSync()

        return updated
    }

    /// 保存 `saveSuperRightClickSettings` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    private func saveSuperRightClickSettings(_ superRightClickSettings: SuperRightClickSettings) throws -> AppSettings {
        var updated = settings
        updated.superRightClick = superRightClickSettings

        try preferenceRepository.save(updated)
        settings = updated
        onSettingsChanged(updated)
        startSuperRightClickMonitor()
        scheduleSync()

        return updated
    }

    /// 保存 `saveWindowLayoutSettings` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    private func saveWindowLayoutSettings(_ windowLayoutSettings: WindowLayoutSettings) throws -> AppSettings {
        var updated = settings
        updated.windowLayout = windowLayoutSettings

        try preferenceRepository.save(updated)
        settings = updated
        onSettingsChanged(updated)
        scheduleSync()

        return updated
    }

    /// 保存 `saveAppearanceMode` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    private func saveAppearanceMode(_ appearanceMode: AppAppearanceMode) throws -> AppSettings {
        var updated = settings
        updated.appearanceMode = appearanceMode

        try preferenceRepository.save(updated)
        settings = updated
        onSettingsChanged(updated)
        scheduleSync()

        return updated
    }

    /// 保存 `saveScreenCaptureSettings` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    private func saveScreenCaptureSettings(_ screenCaptureSettings: ScreenCaptureSettings) -> Bool {
        var updated = settings
        updated.screenCapture = screenCaptureSettings

        do {
            try preferenceRepository.save(updated)
            settings = updated
            scheduleSync()
            return true
        } catch {
            logger.error("screen capture settings save failed: \(error)")
            return false
        }
    }

    /// 保存 `saveSyncSettings` 接收的应用运行时与 AppKit 集成数据，并保持既有持久化约束。
    private func saveSyncSettings(_ syncSettings: SyncSettings) throws -> AppSettings {
        if syncSettings.isEnabled, syncFolderURL == nil {
            throw AppEnvironmentError.syncFolderUnavailable
        }
        var updated = settings
        updated.sync = syncSettings

        let wasEnabled = settings.sync.isEnabled
        if !syncSettings.isEnabled {
            syncCoordinator.setEnabled(false)
        }
        do {
            try preferenceRepository.save(
                updated,
                deviceSyncEnabled: syncSettings.isEnabled
            )
        } catch {
            if wasEnabled {
                syncCoordinator.setEnabled(true)
            }
            throw error
        }
        settings = updated
        onSettingsChanged(updated)
        syncCoordinator.updateConfiguration(
            historyLimit: updated.clipboard.maxHistoryCount,
            clipboardScope: updated.sync.clipboardScope,
            storageLimit: updated.sync.storageLimit
        )
        if syncSettings.isEnabled {
            syncCoordinator.setEnabled(true)
        }
        return updated
    }

    /// 应用远端合并后的偏好，同时保留仅属于当前设备的同步开关、缓存路径和凭据。
    private func applyRemoteSettings(_ remoteSettings: AppSettings) {
        do {
            var merged = try preferenceRepository.load() ?? remoteSettings
            // API Key 的真实来源是独立加密凭据存储，远端偏好不得覆盖当前内存中的值。
            merged.translation.apiKey = settings.translation.apiKey
            merged.sync.isEnabled = settings.sync.isEnabled
            merged.clipboard.cacheStoragePath = settings.clipboard.cacheStoragePath
            merged.clipboard.maxCacheMegabytes = settings.clipboard.maxCacheMegabytes
            let shouldRestartSuperRightClickMonitor =
                merged.superRightClick != settings.superRightClick
                || merged.translation != settings.translation
            settings = merged
            syncModel.remoteSettings = merged
            Task { await clipboardPollingWorker.updateSettings(merged) }
            syncCoordinator.updateConfiguration(
                historyLimit: merged.clipboard.maxHistoryCount,
                clipboardScope: merged.sync.clipboardScope,
                storageLimit: merged.sync.storageLimit
            )
            onSettingsChanged(merged)
            if shouldRestartSuperRightClickMonitor {
                startSuperRightClickMonitor()
            }
            clipboardModel.refresh()
        } catch {
            logger.error("remote preferences apply failed: \(String(reflecting: type(of: error)))")
        }
    }

    /// 安排或刷新 `scheduleSync` 对应的应用运行时与 AppKit 集成工作。
    func scheduleSync() {
        guard settings.sync.isEnabled else {
            return
        }
        syncCoordinator.syncNow()
    }

    /// 按最新设置和翻译凭据整体重建全局右键监听；权限不足时只记录预检结果。
    func startSuperRightClickMonitor() {
        superRightClickMonitor?.stop()
        superRightClickMonitor = nil

        guard settings.superRightClick.isEnabled else {
            logger.info("super right click monitor not started: disabled in settings")
            return
        }

        let permissionSummary = permissionService.summary()
        if !permissionSummary.canUseSuperRightClick {
            let missingPermissions = permissionSummary.missingSuperRightClickPermissions
                .map(\.rawValue)
                .joined(separator: ",")
            logger.error("super right click permission preflight missing: \(missingPermissions); attempting monitor without prompting")
        }

        let monitor = SuperRightClickMonitor(
            thresholdMilliseconds: settings.superRightClick.longPressMilliseconds,
            service: SuperRightClickService(
                settings: settings.superRightClick,
                selectionCapture: SelectionCaptureService(
                    pasteboard: SystemPasteboardClient(),
                    eventSender: SystemPasteEventSender(),
                    logger: logger
                ),
                classifier: ClipboardClassifier(),
                translationService: TranslationService(
                    provider: BailianTranslationProvider(configuration: settings.translation.bailianConfiguration)
                )
            ),
            logger: logger,
            onResultCaptured: { [weak self] result in
                self?.handleSuperRightClickResult(result)
            }
        )
        guard monitor.start() else {
            return
        }

        superRightClickMonitor = monitor
    }

    /// 以固定间隔触发串行剪贴板轮询，实际读取和持久化由 Actor 隔离。
    private func startClipboardPolling() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollClipboardOnce()
            }
        }
    }

    /// 安排或刷新 `pollClipboardOnce` 对应的应用运行时与 AppKit 集成工作。
    private func pollClipboardOnce() {
        let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        Task { [weak self] in
            guard let self else { return }
            do {
                let recorded = try await clipboardPollingWorker.pollOnce(sourceApp: sourceApp)
                if recorded {
                    clipboardModel.refresh()
                    scheduleSync()
                }
            } catch {
                logger.error("clipboard poll failed: \(error)")
            }
        }
    }

    /// 在面板抢占交互前记住原前台应用，供稍后的自动粘贴恢复目标。
    private func captureFrontmostApplicationBeforePanel() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard frontmostApplication?.processIdentifier != ownProcessIdentifier else {
            logger.info("frontmost app is MacTools; keeping previous paste target")
            return
        }

        appBeforePanel = frontmostApplication
        logger.info("captured paste target: \(frontmostApplication?.localizedName ?? "unknown")")
    }

    /// 执行 `copyFromPanel` 对应的应用运行时与 AppKit 集成输入输出操作。
    private func copyFromPanel(_ item: ClipboardItem) {
        do {
            try clipboardModel.copy(item)
        } catch {
            logger.error("clipboard copy failed: \(error)")
        }
    }

    /// 执行 `pasteFromPanel` 对应的应用运行时与 AppKit 集成输入输出操作。
    private func pasteFromPanel(_ item: ClipboardItem) {
        do {
            try clipboardModel.copy(item)
        } catch {
            logger.error("clipboard copy before paste failed: \(error)")
            return
        }

        guard canPostPasteEvent() else {
            logger.error("paste failed: missing post event permission")
            showPostEventRequiredAlert()
            return
        }

        let targetApplication = appBeforePanel
        mainPanel.hide()
        pasteAfterActivatingTarget(targetApplication)
    }

    /// 激活原前台应用后发送一次粘贴；无目标时使用短延迟兜底。
    private func pasteAfterActivatingTarget(_ targetApplication: NSRunningApplication?) {
        pasteActivationAttempt?.cancel()
        pasteActivationAttempt = nil
        guard let targetApplication else {
            logger.error("paste target missing; sending paste after fallback delay")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.clipboardModel.paste()
            }
            return
        }

        let attempt = PasteActivationAttempt(
            targetApplication: targetApplication,
            notificationCenter: NSWorkspace.shared.notificationCenter,
            logger: logger,
            paste: { [weak self] in
                self?.clipboardModel.paste()
            },
            onFinish: { [weak self] attempt in
                guard self?.pasteActivationAttempt === attempt else { return }
                self?.pasteActivationAttempt = nil
            }
        )
        pasteActivationAttempt = attempt
        attempt.start()
    }

    /// 判断 `canPostPasteEvent` 所描述的应用运行时与 AppKit 集成条件是否成立。
    private func canPostPasteEvent() -> Bool {
        let summary = permissionService.summary()
        if summary.canPasteAutomatically {
            return true
        }

        return permissionService.requestPostEventPermission()
    }

    /// 处理 `handleSuperRightClickResult` 对应的应用运行时与 AppKit 集成事件，并返回或发布处理结果。
    private func handleSuperRightClickResult(_ result: SuperRightClickResult) {
        switch SuperRightClickPresentationRouter.route(
            for: result.item.kind,
            sourceApplication: result.sourceApplication
        ) {
        case .text:
            finderFolderResolutionCoordinator.cancel()
            contextPanel.showText(
                originalText: result.item.text ?? "",
                translation: result.translation,
                isTranslationLoading: result.isTranslationPending,
                reposition: result.translation == nil
            )
        case .fileSystem:
            finderFolderResolutionCoordinator.cancel()
            contextPanel.show(item: result.item)
        case .finderCurrentFolder:
            let sourceApplication = result.sourceApplication
            finderFolderResolutionCoordinator.replace(
                operation: { [finderCurrentFolderResolver] in
                    await finderCurrentFolderResolver.currentFolderURL(
                        processIdentifier: sourceApplication?.processIdentifier
                    )
                },
                completion: { [weak self] folderURL in
                    self?.showFinderCurrentFolder(
                        folderURL: folderURL,
                        sourceApplication: sourceApplication
                    )
                }
            )
        case .windowLayoutOnly:
            finderFolderResolutionCoordinator.cancel()
            contextPanel.showWindowLayoutOnly()
        }
    }

    /// 展示 `showFinderCurrentFolder` 对应的应用运行时与 AppKit 集成界面或系统位置。
    private func showFinderCurrentFolder(
        folderURL: URL?,
        sourceApplication: SuperRightClickSourceApplication?
    ) {
        guard let folderURL else {
            logger.error("finder current folder unavailable; showing window layouts only")
            contextPanel.showWindowLayoutOnly()
            return
        }

        let path = folderURL.path
        let displayTitle = folderURL.lastPathComponent.isEmpty
            ? path
            : folderURL.lastPathComponent
        let item = ClipboardItem(
            id: UUID(),
            kind: .folder,
            displayTitle: displayTitle,
            searchableText: path,
            text: nil,
            originalPath: path,
            cachedFilePath: nil,
            thumbnailPath: nil,
            sourceApp: sourceApplication?.localizedName ?? "访达",
            createdAt: Date(),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )

        contextPanel.show(item: item, presentation: .finderCurrentDirectory)
    }

    /// 展示 `showPostEventRequiredAlert` 对应的应用运行时与 AppKit 集成界面或系统位置。
    private func showPostEventRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "需要自动粘贴权限"
        alert.informativeText = "内容已复制到剪贴板。自动粘贴需要把 Command+V 发送到当前应用，请在系统设置里允许 MacTools 发送键盘事件。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            permissionService.openSystemSettings(for: .postEvent)
        }
    }

    /// 解析并返回 `selectSyncFolder` 对应的应用运行时与 AppKit 集成结果。
    private func selectSyncFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 MacTools 同步文件夹"
        panel.prompt = "选择"
        panel.message = "可选择 iCloud Drive 中的目录；MacTools 会在其中使用“MacTools Sync”文件夹。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let rootURL: URL
        if selectedURL.lastPathComponent == DriveSyncStore.rootDirectoryName
            || FileManager.default.fileExists(
                atPath: selectedURL.appendingPathComponent("protocol.json").path
            ) {
            rootURL = selectedURL
        } else {
            rootURL = selectedURL.appendingPathComponent(
                DriveSyncStore.rootDirectoryName,
                isDirectory: true
            )
        }

        syncFolderSelectionGeneration += 1
        let selectionGeneration = syncFolderSelectionGeneration
        let previousStatus = syncModel.status
        let initialCapacity = settings.sync.storageLimit
        let worker = syncFolderPreparationWorker
        syncModel.status = .preparingFolder

        Task { @MainActor [weak self] in
            do {
                let prepared = try await worker.prepare(
                    rootURL: rootURL,
                    securityScopedURL: selectedURL,
                    initialCapacity: initialCapacity
                )
                guard let self,
                      selectionGeneration == syncFolderSelectionGeneration else {
                    return
                }
                try await worker.persist(prepared)
                guard selectionGeneration == syncFolderSelectionGeneration else {
                    return
                }
                syncFolderURL = prepared.rootURL
                syncModel.folderPath = prepared.rootURL.path
                syncModel.folderIsUbiquitous = prepared.isUbiquitous
                syncCoordinator.setRootURL(prepared.rootURL)
                if settings.sync.isEnabled {
                    syncCoordinator.syncNow()
                } else {
                    syncModel.status = .off
                }
            } catch let error as DriveSyncStoreError {
                guard let self,
                      selectionGeneration == syncFolderSelectionGeneration else {
                    return
                }
                if case .incompatibleProtocol = error {
                    syncModel.status = .protocolIncompatible
                } else {
                    syncModel.status = previousStatus
                }
                logger.error(
                    "sync folder selection failed: \(String(reflecting: type(of: error)))"
                )
            } catch {
                guard let self,
                      selectionGeneration == syncFolderSelectionGeneration else {
                    return
                }
                syncModel.status = previousStatus
                logger.error(
                    "sync folder selection failed: \(String(reflecting: type(of: error)))"
                )
            }
        }
    }

    /// 展示 `openSyncFolder` 对应的应用运行时与 AppKit 集成界面或系统位置。
    private func openSyncFolder() {
        guard let syncFolderURL else { return }
        NSWorkspace.shared.open(syncFolderURL)
    }

    /// 展示 `openClipboardStorageFolder` 对应的应用运行时与 AppKit 集成界面或系统位置。
    private func openClipboardStorageFolder() {
        NSWorkspace.shared.open(defaultClipboardCacheDirectory)
    }

    /// 解析并返回 `resolveSyncFolderBookmark` 对应的应用运行时与 AppKit 集成结果。
    private static func resolveSyncFolderBookmark(_ bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), !isStale else {
            return nil
        }
        return url
    }

    /// 计算并返回 `applicationSupportDirectory` 对应的应用运行时与 AppKit 集成数据或状态结果。
    private static func applicationSupportDirectory() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("MacTools", isDirectory: true)
    }
}
