import AppKit
import MacToolsCore

/// 事件拦截交给独立运行循环；主 Actor 只装配选区、翻译和带身份的展示结果。
@MainActor
final class SuperRightClickMonitor {
    private let thresholdMilliseconds: Int
    private let service: SuperRightClickService
    private let logger: Logger
    private let onGestureBegan: (UUID, TimeInterval) -> Void
    private let onCancelled: () -> Void
    private let onResultCaptured: (SuperRightClickResult, UUID) -> Void
    private var eventTap: RightClickEventTap?
    private var lifecycleID = UUID()
    private var gestureID: UUID?
    private var captureTask: Task<Void, Never>?

    init(thresholdMilliseconds: Int, service: SuperRightClickService, logger: Logger,
         onGestureBegan: @escaping (UUID, TimeInterval) -> Void,
         onCancelled: @escaping () -> Void,
         onResultCaptured: @escaping (SuperRightClickResult, UUID) -> Void) {
        self.thresholdMilliseconds = thresholdMilliseconds
        self.service = service
        self.logger = logger
        self.onGestureBegan = onGestureBegan
        self.onCancelled = onCancelled
        self.onResultCaptured = onResultCaptured
    }

    func start() -> Bool {
        stop()
        let lifecycle = lifecycleID
        let tap = RightClickEventTap(thresholdMilliseconds: thresholdMilliseconds, logger: logger) { [weak self] output in
            // 同一生产线程提交到同一队列，保持 began/trigger/cancel 的顺序。
            DispatchQueue.main.async {
                guard let self, self.lifecycleID == lifecycle else { return }
                self.handle(output)
            }
        }
        guard tap.start() else {
            logger.error("super right click event tap could not be installed")
            return false
        }
        eventTap = tap
        logger.info("super right click event tap installed on dedicated run loop")
        return true
    }

    func stop() {
        lifecycleID = UUID()
        cancelCapture()
        eventTap?.stop()
        eventTap = nil
        onCancelled()
    }

    func cancelCapture() {
        gestureID = nil
        captureTask?.cancel()
        captureTask = nil
    }

    /// 内部入口也供回归测试驱动生产任务生命周期，不依赖系统权限或真实剪贴板。
    func handle(_ output: RightClickEventProcessor.Output) {
        switch output {
        case let .began(id, milliseconds):
            cancelCapture()
            gestureID = id
            onGestureBegan(id, Double(milliseconds) / 1_000)
        case .cancelled:
            cancelCapture()
            onCancelled()
        case .triggered(let id):
            guard gestureID == id, captureTask == nil else { return }
            logger.info("super right click long press triggered gesture=\(id)")
            let application = NSWorkspace.shared.frontmostApplication
            let source = application.map {
                SuperRightClickSourceApplication(localizedName: $0.localizedName,
                    bundleIdentifier: $0.bundleIdentifier, processIdentifier: $0.processIdentifier)
            }
            let service = service
            captureTask = Task { [weak self] in
                let result = await service.handleDecision(.triggerSuperRightClick, sourceApplication: source)
                guard !Task.isCancelled, self?.gestureID == id, let result else { return }
                self?.onResultCaptured(result, id)
                guard result.isTranslationPending, let text = result.item.text else { return }
                let translation = await service.translateText(text)
                guard !Task.isCancelled, self?.gestureID == id else { return }
                var translated = result
                translated.translation = translation
                translated.isTranslationPending = false
                self?.onResultCaptured(translated, id)
            }
        }
    }

    deinit {
        captureTask?.cancel()
        eventTap?.stop()
    }
}
