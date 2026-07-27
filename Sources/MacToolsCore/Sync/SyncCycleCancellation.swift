import Foundation

/// 表示同步周期已经被关闭、目录切换或更新后的生命周期代际淘汰。
public enum SyncCycleCancellationError: Error, Equatable, Sendable {
    case cancelled
}

/// 由运行时 Coordinator 提供的协作式取消检查，不依赖 AppKit 生命周期实现。
public struct SyncCycleCancellation: Sendable {
    public typealias IsCancelled = @Sendable () -> Bool

    private let isCancelled: IsCancelled

    public init(isCancelled: @escaping IsCancelled = { false }) {
        self.isCancelled = isCancelled
    }

    public func check() throws {
        if isCancelled() {
            throw SyncCycleCancellationError.cancelled
        }
    }
}
