import Foundation

/// 将面板、延迟点击和异步结果绑定到同一手势；时间与 NSEvent.timestamp 同源。
public struct SuperRightClickPresentationSession {
    private var id: UUID?
    private var startedAt: TimeInterval = 0

    public init() {}

    public mutating func begin(id: UUID, at timestamp: TimeInterval) {
        self.id = id
        startedAt = timestamp
    }

    public mutating func dismiss() { id = nil }

    public func accepts(_ id: UUID) -> Bool { self.id == id }

    public func acceptsDismissal(at eventTimestamp: TimeInterval) -> Bool {
        // CGEvent 转毫秒会向下取整；忽略触发 down 在同一毫秒内的原始时间。
        id != nil && eventTimestamp >= startedAt + 0.001
    }
}
