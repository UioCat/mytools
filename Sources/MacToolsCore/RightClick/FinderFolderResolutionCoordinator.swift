import Foundation

@MainActor
public final class FinderFolderResolutionCoordinator {
    private var task: Task<Void, Never>?
    private var generation: UInt = 0

    public init() {}

    public func replace<Value>(
        operation: @escaping () async -> Value,
        completion: @escaping (Value) -> Void
    ) {
        task?.cancel()
        generation += 1
        let requestGeneration = generation

        task = Task { [weak self] in
            guard !Task.isCancelled else {
                return
            }
            let value = await operation()
            guard !Task.isCancelled,
                  let self,
                  self.generation == requestGeneration else {
                return
            }

            self.task = nil
            completion(value)
        }
    }

    public func cancel() {
        task?.cancel()
        generation += 1
        task = nil
    }
}
