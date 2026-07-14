@MainActor
public final class ScreenCapturePreparationCache<Value> {
    private let loader: () async throws -> Value
    private var task: Task<Value, Error>?
    private var generation = 0

    public init(loader: @escaping () async throws -> Value) {
        self.loader = loader
    }

    public func value() async throws -> Value {
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
            if self.generation == generation {
                self.task = nil
            }
            throw error
        }
    }

    public func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
    }
}
