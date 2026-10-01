// AppEnvironment 的翻译凭据启动与迁移流程。
// 负责协调本地加密信封、云端副本和旧 Keychain 来源，不保存明文副本。

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
        case .record(let record):
            guard CredentialRuntimeUpdatePolicy.shouldReloadLocal(
                loadFinished: credentialLoadFinished,
                isUnavailable: translationCredentialModel.isUnavailable,
                settingsValue: fallback,
                cloudValue: record.value
            ) else {
                if let legacySettingsURL { redactLegacyCredential(at: legacySettingsURL) }
                return
            }
            let credentialAccess = credentialAccess
            Task { @MainActor [weak self] in
                await CredentialLoadRequest.perform(
                    isCurrent: { self.map { generation == $0.credentialLoadGeneration } ?? false },
                    load: { try await credentialAccess.loadLocal(.bailianAPIKey, fallback: fallback) },
                    onLoaded: { result in
                        self?.applyCredentialLoadResult(result, generation: generation, legacySettingsURL: legacySettingsURL)
                    },
                    onFailure: { error in
                        self?.translationCredentialModel.isUnavailable = true
                        self?.logger.error("synced credential unavailable: \(String(reflecting: type(of: error)))")
                    }
                )
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

    /// 仅应用当前代际且发生变化的凭据结果，并在迁移成功后擦除旧设置中的明文副本。
    func applyCredentialLoadResult(
        _ result: CredentialAccessCoordinator.LoadResult,
        generation: Int,
        legacySettingsURL: URL?
    ) {
        guard generation == credentialLoadGeneration else { return }
        let decision = CredentialRuntimeUpdatePolicy.decision(
            settingsValue: settings.translation.apiKey,
            publishedValue: translationCredentialModel.apiKey,
            isUnavailable: translationCredentialModel.isUnavailable,
            loadedValue: result.value
        )
        credentialLoadFinished = true
        if decision.shouldRefreshDependentServices {
            settings.translation.apiKey = result.value
        }
        if decision.shouldUpdatePublishedValue {
            translationCredentialModel.apiKey = result.value
        }
        if decision.shouldClearUnavailableState {
            translationCredentialModel.isUnavailable = false
        }
        if result.shouldRedactLegacy, let legacySettingsURL {
            redactLegacyCredential(at: legacySettingsURL)
        }
        guard decision.shouldRefreshDependentServices else { return }
        onSettingsChanged(settings)
        startSuperRightClickMonitor()
    }

    /// 调整 `redactLegacyCredential` 涉及的应用运行时与 AppKit 集成状态，并保持迁移或恢复语义。
    func redactLegacyCredential(at url: URL) {
        let credentialAccess = credentialAccess
        Task { @MainActor [weak self] in
            do {
                try await credentialAccess.redactLegacySettings(at: url)
            } catch {
                self?.logger.error(
                    "legacy credential redaction failed: \(String(reflecting: type(of: error)))"
                )
            }
        }
    }
}

/// 隔离异步存储边界，统一翻译草稿与运行时设置的发布。
@MainActor
final class TranslationSettingsSaveCoordinator {
    struct Dependencies {
        var currentSettings: @MainActor () -> AppSettings
        var saveCredential: @MainActor (String) async throws -> Void
        var persistSettings: @MainActor (AppSettings) throws -> Void
        var publishSettings: @MainActor (AppSettings) -> Void
        var credentialSaveBegan: @MainActor () -> Void
        var credentialSaveSucceeded: @MainActor (String) -> Void
        var credentialSaveFailed: @MainActor () -> Void
        var reloadCredentialAfterFailure: @MainActor () async throws -> String? = { nil }
    }

    private var saveGeneration = 0
    private var credentialWrite: Task<String, Error>?
    private var credentialWriteGeneration: Int?

    func save(
        _ draft: TranslationSettings,
        apiKeyWasEdited: Bool,
        dependencies: Dependencies
    ) async throws -> AppSettings {
        saveGeneration += 1
        let generation = saveGeneration
        if apiKeyWasEdited {
            dependencies.credentialSaveBegan()
            let previousWrite = credentialWrite
            let apiKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            // 加密写入不能逆序完成；前一次失败不阻止后续明确输入的新密钥。
            credentialWrite = Task { @MainActor in
                if let previousWrite { _ = try? await previousWrite.value }
                try await dependencies.saveCredential(apiKey)
                // 已提交的凭据独立于普通翻译草稿代际；下一次写入必须以此为运行时来源。
                dependencies.credentialSaveSucceeded(apiKey)
                return apiKey
            }
            credentialWriteGeneration = generation
        }
        let pendingWrite = credentialWrite
        let pendingWriteGeneration = credentialWriteGeneration
        let savedAPIKey: String?
        do {
            if let pendingWrite {
                savedAPIKey = try await pendingWrite.value
            } else {
                savedAPIKey = nil
            }
        } catch {
            clearCredentialWrite(generation: pendingWriteGeneration)
            guard generation == saveGeneration else { throw CancellationError() }
            // 写入新值失败不代表之前已提交的凭据不可读；在后台重新认证本地信封。
            let retainedAPIKey: String?
            do { retainedAPIKey = try await dependencies.reloadCredentialAfterFailure() }
            catch { retainedAPIKey = nil }
            guard generation == saveGeneration else { throw CancellationError() }
            if let retainedAPIKey { dependencies.credentialSaveSucceeded(retainedAPIKey) }
            else { dependencies.credentialSaveFailed() }
            throw error
        }
        clearCredentialWrite(generation: pendingWriteGeneration)
        guard generation == saveGeneration else { throw CancellationError() }

        // 等待后重新读取完整运行时设置，只合并本次翻译草稿。
        var updated = dependencies.currentSettings()
        var translation = draft.resolvingAPIKey(
            currentAPIKey: savedAPIKey ?? updated.translation.apiKey,
            wasEdited: false
        )
        translation.providerID = TranslationSettings.defaultProviderID
        updated.translation = translation
        // 两种存储不是同一事务；偏好失败时已写入的加密凭据仍然保留。
        try dependencies.persistSettings(updated)
        dependencies.publishSettings(updated)
        return updated
    }

    private func clearCredentialWrite(generation: Int?) {
        guard generation == credentialWriteGeneration else { return }
        credentialWrite = nil
        credentialWriteGeneration = nil
    }
}

/// 将异步加载的成功与失败交付到当前运行时请求。
@MainActor
enum CredentialLoadRequest {
    static func perform<Value: Sendable>(
        isCurrent: @MainActor () -> Bool,
        load: @MainActor () async throws -> Value?,
        onLoaded: @MainActor (Value) -> Void,
        onFailure: @MainActor (Error) -> Void
    ) async {
        guard isCurrent() else { return }
        do {
            guard let value = try await load(), isCurrent() else { return }
            onLoaded(value)
        } catch {
            guard isCurrent() else { return }
            onFailure(error)
        }
    }
}
