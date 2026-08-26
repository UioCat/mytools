// 超级右键的会话级 CGEventTap 监听器。
// 负责区分短按与长按并回放系统短按事件，内容捕获和翻译交给 Core 服务。

import AppKit
import CoreGraphics
import Dispatch
import Foundation
import MacToolsCore

/// 事件 tap 源会先安装到主运行循环，再把这些值转发给主 Actor。
private struct MainRunLoopEventTapInput: @unchecked Sendable {
    let event: CGEvent
    let proxy: CGEventTapProxy
}

/// 管理 `SuperRightClickMonitor` 在应用运行时与 AppKit 集成中的生命周期、依赖和可变状态。
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

    /// 创建 `SuperRightClickMonitor`，保存传入依赖并建立初始状态。
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

    /// 在会话级事件 tap 上监听并抑制右键按下/抬起事件，以区分短按和长按。
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

    nonisolated private static let handleEventTap: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<SuperRightClickMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        return monitor.handleEvent(type: type, event: event, proxy: proxy)
    }

    /// 停止接收新事件并清理计时器；已启动的选区或翻译异步任务不会在此处取消。
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

    /// 在事件 tap 回调中同步决定是否吞掉原事件，并在系统停用 tap 后立即恢复。
    nonisolated private func handleEvent(
        type: CGEventType,
        event: CGEvent,
        proxy: CGEventTapProxy
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

        let input = MainRunLoopEventTapInput(event: event, proxy: proxy)
        let shouldSuppress = MainActor.assumeIsolated {
            handleEventOnMainActor(type: type, event: input.event, proxy: input.proxy)
        }

        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    /// 处理 `handleEventOnMainActor` 对应的应用运行时与 AppKit 集成事件，并返回或发布处理结果。
    private func handleEventOnMainActor(
        type: CGEventType,
        event: CGEvent,
        proxy: CGEventTapProxy
    ) -> Bool {
        switch type {
        case .rightMouseDown:
            return handleRightMouseDown(event: event)
        case .rightMouseUp:
            return handleRightMouseUp(event: event, proxy: proxy)
        default:
            return false
        }
    }

    /// 缓存被抑制的按下事件并启动轮询计时器，为短按回放保留完整事件对。
    private func handleRightMouseDown(event: CGEvent) -> Bool {
        logger.info("super right click right mouse down")
        pendingSuppressedRightMouseDown = event.copy()
        let route = gestureRouter.handle(
            .pressed(atMilliseconds: eventTimestampMilliseconds(event))
        )
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

    /// 结束计时；若未达到长按阈值，则按原事件 tap 顺序回放系统右键。
    private func handleRightMouseUp(
        event: CGEvent,
        proxy: CGEventTapProxy
    ) -> Bool {
        logger.info("super right click right mouse up")
        longPressTimer?.invalidate()
        longPressTimer = nil
        let route = gestureRouter.handle(
            .released(atMilliseconds: eventTimestampMilliseconds(event))
        )
        if route == .suppressAndReplaySystemRightClick {
            replaySystemRightClick(mouseUpEvent: event, proxy: proxy)
        }
        triggerSuperRightClick(if: route)
        pendingSuppressedRightMouseDown = nil
        return route.shouldSuppressOriginalEvent
    }

    /// 长按成立后先发布可立即展示的捕获结果，再异步补齐可能较慢的翻译内容。
    private func handleLongPressTimer() {
        let route = gestureRouter.handle(.timerFired(atMilliseconds: currentUptimeMilliseconds()))
        triggerSuperRightClick(if: route)
    }

    /// 统一消费定时器或抬起兜底产生的长按路由，避免展示链路分叉。
    private func triggerSuperRightClick(if route: RightClickEventRoute) {
        guard route == .suppressAndTriggerSuperRightClick else {
            return
        }

        longPressTimer?.invalidate()
        longPressTimer = nil
        logger.info("super right click long press triggered")
        let sourceApplication = frontmostApplicationContext()

        Task {
            // 首次回调保证菜单尽快出现；翻译完成后的第二次回调用于原位刷新同一内容。
            let result = await service.handleDecision(
                .triggerSuperRightClick,
                sourceApplication: sourceApplication
            )
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

    /// 更新 `replaySystemRightClick` 对应的交互状态，并保持当前选择或展示约束。
    private func replaySystemRightClick(
        mouseUpEvent: CGEvent,
        proxy: CGEventTapProxy
    ) {
        guard let mouseDownEvent = pendingSuppressedRightMouseDown?.copy(),
              let mouseUpEvent = mouseUpEvent.copy() else {
            logger.error("super right click could not replay short system right click")
            return
        }

        mouseDownEvent.tapPostEvent(proxy)
        mouseUpEvent.tapPostEvent(proxy)
    }

    /// 使用 Quartz 事件发生时间计算真实按压时长，避免主线程延迟压缩按下与抬起间隔。
    private func eventTimestampMilliseconds(_ event: CGEvent) -> Int {
        guard event.timestamp > 0 else {
            return currentUptimeMilliseconds()
        }
        return Int(event.timestamp / 1_000_000)
    }

    /// Quartz 事件时间与 Dispatch 单调时钟都以系统启动为基准，可安全用于定时器比较。
    private func currentUptimeMilliseconds() -> Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// 计算并返回 `frontmostApplicationContext` 对应的应用运行时与 AppKit 集成数据或状态结果。
    private func frontmostApplicationContext() -> SuperRightClickSourceApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return SuperRightClickSourceApplication(
            localizedName: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier
        )
    }
}
