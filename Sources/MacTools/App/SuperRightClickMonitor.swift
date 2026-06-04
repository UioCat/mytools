import AppKit
import CoreGraphics
import Foundation
import MacToolsCore

@MainActor
final class SuperRightClickMonitor {
    private let service: SuperRightClickService
    private let logger: Logger
    private let onItemCaptured: (ClipboardItem) -> Void
    private var stateMachine: RightClickStateMachine
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var longPressTimer: Timer?
    private var shouldSuppressNextRightMouseUp = false

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

        let mask = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.handleEventTap,
            userInfo: userInfo
        ) else {
            logger.error("super right click event tap could not be installed")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
    }

    nonisolated private static let handleEventTap: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<SuperRightClickMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return monitor.handleEvent(type: type, event: event)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        shouldSuppressNextRightMouseUp = false
    }

    nonisolated private func handleEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = MainActor.assumeIsolated {
            handleEventOnMainActor(type: type)
        }

        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    private func handleEventOnMainActor(type: CGEventType) -> Bool {
        switch type {
        case .rightMouseDown:
            handleRightMouseDown()
            return false
        case .rightMouseUp:
            return handleRightMouseUp()
        default:
            return false
        }
    }

    private func handleRightMouseDown() {
        shouldSuppressNextRightMouseUp = false
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

    private func handleRightMouseUp() -> Bool {
        longPressTimer?.invalidate()
        longPressTimer = nil
        _ = stateMachine.handle(.released(atMilliseconds: currentMilliseconds()))
        let shouldSuppress = shouldSuppressNextRightMouseUp
        shouldSuppressNextRightMouseUp = false
        return shouldSuppress
    }

    private func handleLongPressTimer() {
        let decision = stateMachine.handle(.timerFired(atMilliseconds: currentMilliseconds()))
        guard decision == .triggerSuperRightClick else {
            return
        }

        longPressTimer?.invalidate()
        longPressTimer = nil
        shouldSuppressNextRightMouseUp = true

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
