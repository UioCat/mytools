// `AppEnvironment+Credentials` 的应用运行时与 AppKit 集成实现。
// 负责生命周期、面板和 macOS 能力接线，不承载可复用的持久化规则。

import Foundation
import MacToolsCore

/// 扩展 `AppEnvironment`，补充本文件所需的应用运行时与 AppKit 集成能力。
@MainActor
extension AppEnvironment {
    /// 优先读取本地加密凭据；需要时等待云端副本，最后才尝试只读旧存储迁移。
    func loadTranslationCredentialIfNeeded() {
        credentialLoadGeneration += 1
        let generation = credentialLoadGeneration
        // 每条异步路径提交结果前都核对代际，避免旧加载覆盖用户刚保存的新密钥。
        credentialLoadFinished = false
        credentialLegacyLoadStarted = false
        let fallback = settings.translation.apiKey
        let credentialAccess = credentialAccess
        let legacySettingsURL = legacySettingsURL
        let shouldCheckCloud = settings.sync.isEnabled && syncFolderURL != nil

        Task { @MainActor [weak self] in
            do {
                if let result = try await credentialAccess.loadLocal(
                    .bailianAPIKey,
                    fallback: fallback
                ) {
                    guard let self, generation == credentialLoadGeneration else { return }
                    applyCredentialLoadResult(
                        result,
                        generation: generation,
                        legacySettingsURL: legacySettingsURL
                    )
                    syncCoordinator.syncNow()
                    return
                }
            } catch {
                guard let self, generation == credentialLoadGeneration else { return }
                logger.error(
                    "local credential unavailable: \(String(reflecting: type(of: error)))"
                )
                if shouldCheckCloud {
                    syncCoordinator.bootstrapCredentialAndSync()
                    return
                }
                credentialLoadFinished = true
                settings.translation.apiKey = fallback
                translationCredentialModel.apiKey = fallback
                translationCredentialModel.isUnavailable = true
                return
            }

            guard let self, generation == credentialLoadGeneration else { return }
            if shouldCheckCloud {
                syncCoordinator.bootstrapCredentialAndSync()
                return
            }
            beginLegacyCredentialLoadIfNeeded(
                generation: generation,
                fallback: fallback,
                legacySettingsURL: legacySettingsURL
            )
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  generation == credentialLoadGeneration,
                  !credentialLoadFinished else { return }
            translationCredentialModel.isUnavailable = true
            logger.error("Bailian credential loading is taking longer than expected")
        }
    }

    /// 根据云端凭据状态继续本地解密、等待下载或回退到旧存储迁移。
    func handleCredentialCloudState(
        _ state: ICloudDriveSyncCoordinator.CredentialCloudState
    ) {
        let generation = credentialLoadGeneration
        let fallback = settings.translation.apiKey
        let legacySettingsURL = legacySettingsURL

        switch state {
        case .record:
            let credentialAccess = credentialAccess
            Task { @MainActor [weak self] in
                guard let self, generation == credentialLoadGeneration else { return }
                do {
                    guard let result = try await credentialAccess.loadLocal(
                        .bailianAPIKey,
                        fallback: fallback
                    ) else {
                        return
                    }
                    guard generation == credentialLoadGeneration else { return }
                    applyCredentialLoadResult(
                        result,
                        generation: generation,
                        legacySettingsURL: legacySettingsURL
                    )
                } catch {
                    translationCredentialModel.isUnavailable = true
                    logger.error(
                        "synced credential unavailable: \(String(reflecting: type(of: error)))"
                    )
                }
            }
        case .noRecord, .unavailable:
            guard !credentialLoadFinished else { return }
            beginLegacyCredentialLoadIfNeeded(
                generation: generation,
                fallback: fallback,
                legacySettingsURL: legacySettingsURL
            )
        case .waitingForDownload:
            guard !credentialLoadFinished else { return }
            translationCredentialModel.isUnavailable = true
        case .failed:
            guard !credentialLoadFinished else { return }
            translationCredentialModel.isUnavailable = true
            logger.error("cloud credential synchronization failed")
        }
    }

    /// 每个加载代际至多启动一次旧凭据读取，成功后由统一入口应用并触发同步。
    func beginLegacyCredentialLoadIfNeeded(
        generation: Int,
        fallback: String,
        legacySettingsURL: URL?
    ) {
        guard generation == credentialLoadGeneration,
              !credentialLoadFinished,
              !credentialLegacyLoadStarted else {
            return
        }
        credentialLegacyLoadStarted = true
        let credentialAccess = credentialAccess
        Task { @MainActor [weak self] in
            do {
                let result = try await credentialAccess.load(
                    .bailianAPIKey,
                    fallback: fallback
                )
                guard let self, generation == credentialLoadGeneration else { return }
                applyCredentialLoadResult(
                    result,
                    generation: generation,
                    legacySettingsURL: legacySettingsURL
                )
                scheduleSync()
            } catch {
                guard let self, generation == credentialLoadGeneration else { return }
                credentialLoadFinished = true
                settings.translation.apiKey = fallback
                translationCredentialModel.apiKey = fallback
                translationCredentialModel.isUnavailable = true
                logger.error(
                    "Bailian credential unavailable: \(String(reflecting: type(of: error)))"
                )
            }
        }
    }

    /// 仅应用当前代际的凭据结果，并在迁移成功后擦除旧设置中的明文副本。
    func applyCredentialLoadResult(
        _ result: CredentialAccessCoordinator.LoadResult,
        generation: Int,
        legacySettingsURL: URL?
    ) {
        guard generation == credentialLoadGeneration else { return }
        credentialLoadFinished = true
        settings.translation.apiKey = result.value
        translationCredentialModel.apiKey = result.value
        translationCredentialModel.isUnavailable = false
        if result.shouldRedactLegacy, let legacySettingsURL {
            redactLegacyCredential(at: legacySettingsURL)
        }
        onSettingsChanged(settings)
        startSuperRightClickMonitor()
    }

    /// 调整 `redactLegacyCredential` 涉及的应用运行时与 AppKit 集成状态，并保持迁移或恢复语义。
    func redactLegacyCredential(at url: URL) {
        do {
            let legacyStore = SettingsStore(fileURL: url)
            var legacySettings = try legacyStore.load()
            guard !legacySettings.translation.apiKey.isEmpty else { return }
            legacySettings.translation.apiKey = ""
            try legacyStore.save(legacySettings)
        } catch {
            logger.error(
                "legacy credential redaction failed: \(String(reflecting: type(of: error)))"
            )
        }
    }
}
