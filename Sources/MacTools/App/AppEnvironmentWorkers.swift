import AppKit
import Foundation
import MacToolsCore

actor ClipboardPollingWorker {
    private let service: ClipboardService

    init(service: ClipboardService) {
        self.service = service
    }

    func pollOnce(sourceApp: String?) throws -> Bool {
        try service.pollOnce(sourceApp: sourceApp)
    }

    func updateSettings(_ settings: AppSettings) {
        service.updateSettings(settings)
    }
}

actor AppMaintenanceWorker {
    private let repository: ClipboardRepository
    private let payloadStore: PayloadStore
    private let usesPersistentDatabase: Bool
    private let logger: Logger
    private var hasRun = false

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

@MainActor
final class PasteActivationAttempt {
    private let targetApplication: NSRunningApplication
    private let notificationCenter: NotificationCenter
    private let logger: Logger
    private let paste: () -> Void
    private let onFinish: (PasteActivationAttempt) -> Void
    private var observer: NSObjectProtocol?
    private var didPaste = false

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

    func cancel() {
        guard !didPaste else { return }
        didPaste = true
        removeObserver()
        onFinish(self)
    }

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

    private func removeObserver() {
        guard let observer else { return }
        notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
