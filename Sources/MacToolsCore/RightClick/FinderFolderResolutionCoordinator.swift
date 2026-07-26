// `FinderFolderResolutionCoordinator` 的超级右键领域实现。
// 负责事件决策、选区解析和动作路由，不安装系统级事件监听。

import Foundation

/// 串行管理 Finder 目录解析任务，并使用 generation 阻止旧请求覆盖新结果。
@MainActor
public final class FinderFolderResolutionCoordinator {
    private var task: Task<Void, Never>?
    private var generation: UInt = 0

    /// 创建 `FinderFolderResolutionCoordinator`，保存传入依赖并建立初始状态。
    public init() {}

    /// 取消当前解析并启动新请求；仅最新 generation 可以发布完成值。
    public func replace<Value: Sendable>(
        operation: @escaping @Sendable () async -> Value,
        completion: @escaping (Value) -> Void
    ) {
        // Task 取消是合作式的，因此还要递增 generation，拦截未及时响应取消的旧操作。
        task?.cancel()
        generation += 1
        let requestGeneration = generation

        task = Task { [weak self] in
            guard !Task.isCancelled else {
                return
            }
            let value = await operation()
            // operation 可能忽略取消；完成前再次核对 generation 才能安全回写界面。
            guard !Task.isCancelled,
                  let self,
                  self.generation == requestGeneration else {
                return
            }

            self.task = nil
            completion(value)
        }
    }

    /// 取消当前请求并使所有已发出的完成回调失效。
    public func cancel() {
        task?.cancel()
        generation += 1
        task = nil
    }
}
