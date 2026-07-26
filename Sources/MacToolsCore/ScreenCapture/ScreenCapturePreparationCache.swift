// `ScreenCapturePreparationCache` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

/// 复用同一屏幕捕获准备任务，并在失效后阻止旧任务清除新缓存。
@MainActor
public final class ScreenCapturePreparationCache<Value: Sendable> {
    private let loader: () async throws -> Value
    private var task: Task<Value, Error>?
    private var generation = 0

    /// 创建 `ScreenCapturePreparationCache`，保存传入依赖并建立初始状态。
    public init(loader: @escaping () async throws -> Value) {
        self.loader = loader
    }

    /// 返回当前准备结果；并发调用共享同一个 loader 任务。
    public func value() async throws -> Value {
        // 屏幕列表和内容过滤准备成本较高，同一代际只允许存在一个加载任务。
        if let task {
            return try await task.value
        }

        let generation = generation
        let loader = loader
        let task = Task {
            try await loader()
        }
        self.task = task

        do {
            return try await task.value
        } catch {
            // invalidate 后旧任务仍可能抛错，只有同一代际才能清空当前缓存。
            if self.generation == generation {
                self.task = nil
            }
            throw error
        }
    }

    /// 取消当前准备任务并开启新代际，使旧完成结果失效。
    public func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
    }
}
