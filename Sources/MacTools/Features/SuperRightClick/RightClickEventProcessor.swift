import CoreGraphics
import Foundation
import MacToolsCore

/// 仅由事件运行循环访问。测试直接输入 CGEvent，使用同一套生产仲裁逻辑。
final class RightClickEventProcessor {
    enum Output: Sendable {
        case began(UUID, atMilliseconds: Int)
        case triggered(UUID)
        case cancelled
    }

    private var router: RightClickGestureRouter
    private let thresholdMilliseconds: Int
    private var mouseDown: CGEvent?
    private var gestureID: UUID?
    private var triggered = false
    private let output: (Output) -> Void
    private let uptime: () -> Int
    private(set) var deadlineMilliseconds: Int?

    init(thresholdMilliseconds: Int,
         uptime: @escaping () -> Int = { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
         output: @escaping (Output) -> Void) {
        self.thresholdMilliseconds = thresholdMilliseconds
        self.router = RightClickGestureRouter(thresholdMilliseconds: thresholdMilliseconds)
        self.uptime = uptime
        self.output = output
    }

    /// true 表示消费原事件。短按副本只能在当前 tap 回调内向下游投递。
    func process(type: CGEventType, event: CGEvent, replay: (CGEvent) -> Void) -> Bool {
        switch type {
        case .rightMouseDown:
            guard !router.isPressed else { return true }
            guard let copy = event.copy() else { return false }
            let timestamp = eventTimestampMilliseconds(event)
            let id = UUID()
            mouseDown = copy
            gestureID = id
            triggered = false
            deadlineMilliseconds = timestamp + thresholdMilliseconds
            _ = router.handle(.pressed(atMilliseconds: timestamp))
            output(.began(id, atMilliseconds: timestamp))
            return true
        case .rightMouseDragged:
            if router.isPressed, !triggered, let down = mouseDown,
               let deadlineMilliseconds,
               eventTimestampMilliseconds(event) < deadlineMilliseconds {
                let dx = event.location.x - down.location.x
                let dy = event.location.y - down.location.y
                if dx * dx + dy * dy >= 36 {
                    // 阈值内移动超过 6 pt 属于系统拖动；先补齐 down 和当前 drag，
                    // 随后的 drag/up 原样通过，不再为同一手势打开超级右键。
                    replay(down)
                    replay(event)
                    cancel()
                    return true
                }
            }
            // 长按与微小抖动必须包含拖动，不能向目标应用发送缺少 down 的半截手势。
            return router.isPressed
        case .rightMouseUp:
            let route = router.handle(.released(atMilliseconds: eventTimestampMilliseconds(event)))
            deadlineMilliseconds = nil
            if route == .suppressAndReplaySystemRightClick,
               let down = mouseDown?.copy(), let up = event.copy() {
                replay(down)
                replay(up)
                output(.cancelled)
            }
            consume(route)
            mouseDown = nil
            gestureID = nil
            return route.shouldSuppressOriginalEvent
        default:
            return false
        }
    }

    func timerFired() {
        consume(router.handle(.timerFired(atMilliseconds: uptime())))
    }

    func cancel() {
        router.cancel()
        mouseDown = nil
        gestureID = nil
        deadlineMilliseconds = nil
        triggered = false
        output(.cancelled)
    }

    private func consume(_ route: RightClickEventRoute) {
        guard route == .suppressAndTriggerSuperRightClick, !triggered, let gestureID else { return }
        triggered = true
        deadlineMilliseconds = nil
        output(.triggered(gestureID))
    }

    private func eventTimestampMilliseconds(_ event: CGEvent) -> Int {
        event.timestamp > 0 ? Int(event.timestamp / 1_000_000) : uptime()
    }
}
