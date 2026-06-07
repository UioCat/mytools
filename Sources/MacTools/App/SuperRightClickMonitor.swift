import AppKit
import CoreGraphics
import Foundation
import MacToolsCore

@MainActor
final class SuperRightClickMonitor {
    private let service: SuperRightClickService
    private let logger: Logger
    private let onResultCaptured: (SuperRightClickResult) -> Void
    private var stateMachine: RightClickStateMachine
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var globalRightMouseDownMonitor: Any?
    private var globalRightMouseUpMonitor: Any?
    private var longPressTimer: Timer?
    private var shouldSuppressNextRightMouseUp = false

    init(
        thresholdMilliseconds: Int,
        service: SuperRightClickService,
        logger: Logger,
        onResultCaptured: @escaping (SuperRightClickResult) -> Void
    ) {
        self.service = service
        self.logger = logger
        self.onResultCaptured = onResultCaptured
        self.stateMachine = RightClickStateMachine(thresholdMilliseconds: thresholdMilliseconds)
    }

    func start() -> Bool {
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
            return startGlobalMonitorFallback()
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
        logger.info("super right click event tap installed")
        return true
    }

    private func startGlobalMonitorFallback() -> Bool {
        globalRightMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.handleRightMouseDown()
            }
        }
        globalRightMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseUp) { [weak self] _ in
            Task { @MainActor in
                _ = self?.handleRightMouseUp()
            }
        }

        guard globalRightMouseDownMonitor != nil, globalRightMouseUpMonitor != nil else {
            logger.error("super right click global monitor fallback could not be installed")
            stop()
            return false
        }

        logger.info("super right click global monitor fallback installed")
        return true
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
        if let globalRightMouseDownMonitor {
            NSEvent.removeMonitor(globalRightMouseDownMonitor)
        }
        if let globalRightMouseUpMonitor {
            NSEvent.removeMonitor(globalRightMouseUpMonitor)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
        globalRightMouseDownMonitor = nil
        globalRightMouseUpMonitor = nil
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
                logger.error("super right click event tap disabled by system; re-enabling")
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
        logger.info("super right click right mouse down")
        shouldSuppressNextRightMouseUp = false
        _ = stateMachine.handle(.pressed(atMilliseconds: currentMilliseconds()))
        longPressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleLongPressTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        longPressTimer = timer
    }

    private func handleRightMouseUp() -> Bool {
        logger.info("super right click right mouse up")
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
        logger.info("super right click long press triggered")

        Task {
            let result = await service.handleDecision(decision, sourceApp: frontmostApplicationName())
            await MainActor.run {
                guard let result else {
                    return
                }
                logger.info("super right click captured \(result.item.kind.rawValue)")
                onResultCaptured(result)
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
