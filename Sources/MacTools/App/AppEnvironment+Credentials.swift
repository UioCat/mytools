import Foundation
import MacToolsCore

@MainActor
extension AppEnvironment {
    func loadTranslationCredentialIfNeeded() {
        credentialLoadGeneration += 1
        let generation = credentialLoadGeneration
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
                    syncCoordinator.bootstrapCredential()
                    syncCoordinator.syncNow()
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
                syncCoordinator.bootstrapCredential()
                syncCoordinator.syncNow()
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
