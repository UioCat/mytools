// 同步周期的协作式取消令牌。
// 由平台 Coordinator 注入当前 lease 状态，使 Core 周期可在安全检查点停止。

import Foundation

/// 表示同步周期已经被关闭、目录切换或更新后的生命周期代际淘汰。
public enum SyncCycleCancellationError: Error, Equatable, Sendable {
    case cancelled
}

/// 由运行时 Coordinator 提供的协作式取消检查，不依赖 AppKit 生命周期实现。
public struct SyncCycleCancellation: Sendable {
    /// 返回当前周期是否已被配置代际淘汰。
    public typealias IsCancelled = @Sendable () -> Bool

    private let isCancelled: IsCancelled

    /// 注入无副作用的取消状态读取器；默认令牌永不取消。
    public init(isCancelled: @escaping IsCancelled = { false }) {
        self.isCancelled = isCancelled
    }

    /// 在同步阶段边界检查 lease；失效时抛出统一取消错误并停止后续写入。
    public func check() throws {
        if isCancelled() {
            throw SyncCycleCancellationError.cancelled
        }
    }
}
