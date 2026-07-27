// `ScreenCapturePreparationCache` 的截图录屏核心领域实现。
// 负责选择、渲染和会话策略，不直接管理 ScreenCaptureKit 流。

import Foundation

/// 复用同一屏幕捕获准备任务，并在失效后阻止旧任务清除新缓存。
@MainActor
public final class ScreenCapturePreparationCache<Value: Sendable> {
    private let timeToLive: TimeInterval
    private let now: () -> Date
    private let loader: () async throws -> Value
    private var task: Task<Value, Error>?
    private var generation = 0
    private var taskGeneration: Int?
    private var completedAt: Date?

    /// 创建 `ScreenCapturePreparationCache`，保存传入依赖并建立初始状态。
    public init(
        timeToLive: TimeInterval = 5,
        now: @escaping () -> Date = Date.init,
        loader: @escaping () async throws -> Value
    ) {
        self.timeToLive = max(0, timeToLive)
        self.now = now
        self.loader = loader
    }

    /// 返回当前准备结果；并发调用共享同一个 loader 任务。
    public func value() async throws -> Value {
        if let completedAt,
           now().timeIntervalSince(completedAt) > timeToLive {
            invalidate()
        }

        // 屏幕列表和内容过滤准备成本较高，同一代际只允许存在一个加载任务。
        if let task {
            return try await resolve(task, generation: taskGeneration ?? generation)
        }

        let generation = generation
        let loader = loader
        let task = Task {
            try await loader()
        }
        self.task = task
        taskGeneration = generation
        completedAt = nil
        return try await resolve(task, generation: generation)
    }

    /// 取消当前准备任务并开启新代际，使旧完成结果失效。
    public func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
        taskGeneration = nil
        completedAt = nil
    }

    /// 等待共享任务，并只允许当前代际写入成功时间或清理失败任务。
    private func resolve(_ task: Task<Value, Error>, generation: Int) async throws -> Value {
        do {
            let value = try await task.value
            guard self.generation == generation else {
                throw CancellationError()
            }
            if completedAt == nil {
                completedAt = now()
            }
            return value
        } catch {
            // invalidate 后旧任务仍可能抛错，只有同一代际才能清空当前缓存。
            if self.generation == generation {
                self.task = nil
                taskGeneration = nil
                completedAt = nil
            }
            throw error
        }
    }
}
