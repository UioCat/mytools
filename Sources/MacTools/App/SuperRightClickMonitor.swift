import AppKit
import CoreGraphics
import Foundation
import MacToolsCore

@MainActor
final class SuperRightClickMonitor {
    private let service: SuperRightClickService
    private let logger: Logger
    private let onResultCaptured: (SuperRightClickResult) -> Void
    private var gestureRouter: RightClickGestureRouter
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var longPressTimer: Timer?
    private var pendingSuppressedRightMouseDown: CGEvent?
    private static let replayedRightClickUserData: Int64 = 0x4D_54_52_43

    init(
        thresholdMilliseconds: Int,
        service: SuperRightClickService,
        logger: Logger,
        onResultCaptured: @escaping (SuperRightClickResult) -> Void
    ) {
        self.service = service
        self.logger = logger
        self.onResultCaptured = onResultCaptured
        self.gestureRouter = RightClickGestureRouter(thresholdMilliseconds: thresholdMilliseconds)
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
            logger.error("super right click event tap could not be installed; event tap is required to suppress the system menu on long press")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
        logger.info("super right click event tap installed")
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
        eventTap = nil
        eventTapRunLoopSource = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        pendingSuppressedRightMouseDown = nil
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
            handleEventOnMainActor(type: type, event: event)
        }

        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    private func handleEventOnMainActor(type: CGEventType, event: CGEvent) -> Bool {
        if isReplayedSystemRightClick(event) {
            return false
        }

        switch type {
        case .rightMouseDown:
            return handleRightMouseDown(event: event)
        case .rightMouseUp:
            return handleRightMouseUp(event: event)
        default:
            return false
        }
    }

    private func handleRightMouseDown(event: CGEvent? = nil) -> Bool {
        logger.info("super right click right mouse down")
        if let event {
            pendingSuppressedRightMouseDown = event.copy()
        }
        let route = gestureRouter.handle(.pressed(atMilliseconds: currentMilliseconds()))
        longPressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleLongPressTimer()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        longPressTimer = timer
        return route.shouldSuppressOriginalEvent
    }

    private func handleRightMouseUp(event: CGEvent? = nil) -> Bool {
        logger.info("super right click right mouse up")
        longPressTimer?.invalidate()
        longPressTimer = nil
        let route = gestureRouter.handle(.released(atMilliseconds: currentMilliseconds()))
        if route == .suppressAndReplaySystemRightClick, let event {
            replaySystemRightClick(mouseUpEvent: event)
        }
        pendingSuppressedRightMouseDown = nil
        return route.shouldSuppressOriginalEvent
    }

    private func handleLongPressTimer() {
        let route = gestureRouter.handle(.timerFired(atMilliseconds: currentMilliseconds()))
        guard route == .suppressAndTriggerSuperRightClick else {
            return
        }

        longPressTimer?.invalidate()
        longPressTimer = nil
        logger.info("super right click long press triggered")
        let sourceApp = frontmostApplicationName()

        Task {
            let result = await service.handleDecision(.triggerSuperRightClick, sourceApp: sourceApp)
            await MainActor.run {
                guard let result else {
                    return
                }
                logger.info("super right click captured \(result.item.kind.rawValue)")
                onResultCaptured(result)
            }

            guard let result,
                  result.isTranslationPending,
                  let text = result.item.text else {
                return
            }

            let translation = await service.translateText(text)
            var translatedResult = result
            translatedResult.translation = translation
            translatedResult.isTranslationPending = false
            await MainActor.run {
                logger.info("super right click translation completed")
                onResultCaptured(translatedResult)
            }
        }
    }

    private func replaySystemRightClick(mouseUpEvent: CGEvent) {
        guard let mouseDownEvent = pendingSuppressedRightMouseDown?.copy(),
              let mouseUpEvent = mouseUpEvent.copy() else {
            logger.error("super right click could not replay short system right click")
            return
        }

        markAsReplayedSystemRightClick(mouseDownEvent)
        markAsReplayedSystemRightClick(mouseUpEvent)
        mouseDownEvent.post(tap: .cghidEventTap)
        mouseUpEvent.post(tap: .cghidEventTap)
    }

    private func markAsReplayedSystemRightClick(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayedRightClickUserData)
    }

    private func isReplayedSystemRightClick(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.replayedRightClickUserData
    }

    private func currentMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }

    private func frontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
