import AppKit
import Foundation
import MacToolsCore

@MainActor
final class SuperRightClickMonitor {
    private let service: SuperRightClickService
    private let logger: Logger
    private let onItemCaptured: (ClipboardItem) -> Void
    private var stateMachine: RightClickStateMachine
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var longPressTimer: Timer?

    init(
        thresholdMilliseconds: Int,
        service: SuperRightClickService,
        logger: Logger,
        onItemCaptured: @escaping (ClipboardItem) -> Void
    ) {
        self.service = service
        self.logger = logger
        self.onItemCaptured = onItemCaptured
        self.stateMachine = RightClickStateMachine(thresholdMilliseconds: thresholdMilliseconds)
    }

    func start() {
        stop()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.handleRightMouseDown()
            }
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.handleRightMouseUp()
            }
        }
    }

    func stop() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
        }
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
        }
        mouseDownMonitor = nil
        mouseUpMonitor = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func handleRightMouseDown() {
        _ = stateMachine.handle(.pressed(atMilliseconds: currentMilliseconds()))
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleLongPressTimer()
            }
        }
    }

    private func handleRightMouseUp() {
        longPressTimer?.invalidate()
        longPressTimer = nil
        _ = stateMachine.handle(.released(atMilliseconds: currentMilliseconds()))
    }

    private func handleLongPressTimer() {
        let decision = stateMachine.handle(.timerFired(atMilliseconds: currentMilliseconds()))
        guard decision == .triggerSuperRightClick else {
            return
        }

        longPressTimer?.invalidate()
        longPressTimer = nil

        Task {
            let item = await service.handleDecision(decision, sourceApp: frontmostApplicationName())
            await MainActor.run {
                guard let item else {
                    return
                }
                logger.info("super right click captured \(item.kind.rawValue)")
                onItemCaptured(item)
            }
        }
    }

    private func currentMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
