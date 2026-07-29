// ScreenCaptureKit 共享内容和静态截图适配器。
// 负责权限后的内容预热与像素采集，不管理截图编辑或录屏状态。

import AppKit
import CoreGraphics
import MacToolsCore
@preconcurrency import ScreenCaptureKit

/// 描述 `ScreenCaptureError` 在屏幕捕获系统集成中可取的状态、选项或错误。
enum ScreenCaptureError: Error, Equatable {
    case displayUnavailable
    case captureAlreadyRunning
    case recorderNotRunning
    case writerCreationFailed
    case writerFailed
    case downloadsDirectoryUnavailable
    case editorPresentationFailed
}

/// 定义 `ScreenStillCapturing` 在屏幕捕获系统集成中需要满足的能力边界。
@MainActor
protocol ScreenStillCapturing {
    /// 提前加载可共享内容，使用户完成框选后可复用同一次查询结果。
    func prepare() async throws
    /// 根据选区构造过滤器和像素配置，并通过 ScreenCaptureKit 生成静态图像。
    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage
    /// 结束 `invalidatePreparation` 对应的屏幕捕获系统集成流程，并释放或重置相关资源。
    func invalidatePreparation()
}

/// 扩展 `ScreenStillCapturing`，补充本文件所需的屏幕捕获系统集成能力。
extension ScreenStillCapturing {
    /// 异步安排或刷新 `prepare` 对应的屏幕捕获系统集成工作。
    func prepare() async throws {}
    /// 结束 `invalidatePreparation` 对应的屏幕捕获系统集成流程，并释放或重置相关资源。
    func invalidatePreparation() {}
}

/// ScreenCaptureKit 会跨内部采集队列使用这些配置对象。
struct ScreenCaptureSource: @unchecked Sendable {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
}

/// 管理 `SystemScreenCaptureService` 在屏幕捕获系统集成中的生命周期、依赖和可变状态。
@MainActor
final class SystemScreenCaptureService: NSObject, ScreenStillCapturing {
    private let logger: Logger
    private let notificationCenter: NotificationCenter
    private lazy var shareableContentCache = ScreenCapturePreparationCache<SCShareableContent> {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
    }

    /// 创建屏幕采集服务，并监听显示器拓扑变化以清理短期内容缓存。
    init(
        logger: Logger = Logger(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.logger = logger
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// 解除屏幕拓扑通知观察，避免服务释放后继续收到 Objective-C 回调。
    deinit {
        notificationCenter.removeObserver(self)
    }

    /// 异步安排或刷新 `prepare` 对应的屏幕捕获系统集成工作。
    func prepare() async throws {
        _ = try await shareableContent()
    }

    /// 捕获指定区域的静态图像。
    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage {
        let source = try await source(for: selection, purpose: .screenshot)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: source.filter,
                configuration: source.configuration
            )
            logger.info(
                "screen capture system image captured in \(elapsedMilliseconds(since: startedAt)) ms"
            )
            return image
        } catch {
            logger.error(
                "screen capture system image failed after \(elapsedMilliseconds(since: startedAt)) ms"
            )
            throw error
        }
    }

    /// 将全局选区转换为 ScreenCaptureKit 源区域，并按截图或录屏策略计算输出分辨率。
    func source(
        for selection: ScreenCaptureSelection,
        purpose: ScreenCaptureMode
    ) async throws -> ScreenCaptureSource {
        try await source(
            for: selection,
            purpose: purpose,
            retryAfterRefresh: true
        )
    }

    /// 使用缓存快照构造采集源；内容失效或显示器缺失时最多刷新重试一次。
    private func source(
        for selection: ScreenCaptureSelection,
        purpose: ScreenCaptureMode,
        retryAfterRefresh: Bool
    ) async throws -> ScreenCaptureSource {
        do {
            return try await makeSource(for: selection, purpose: purpose)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            shareableContentCache.invalidate()
            guard retryAfterRefresh, CGPreflightScreenCaptureAccess() else {
                throw error
            }
            logger.info("screen capture source refresh requested after preparation failure")
            return try await source(
                for: selection,
                purpose: purpose,
                retryAfterRefresh: false
            )
        }
    }

    /// 查询共享内容并构造过滤器与像素配置。
    private func makeSource(
        for selection: ScreenCaptureSelection,
        purpose: ScreenCaptureMode
    ) async throws -> ScreenCaptureSource {
        let preparationStartedAt = DispatchTime.now().uptimeNanoseconds
        let content: SCShareableContent
        do {
            content = try await shareableContent()
        } catch {
            logger.error(
                "screen capture shareable content failed after "
                    + "\(elapsedMilliseconds(since: preparationStartedAt)) ms"
            )
            throw error
        }
        logger.info(
            "screen capture shareable content ready in "
                + "\(elapsedMilliseconds(since: preparationStartedAt)) ms"
        )

        let configurationStartedAt = DispatchTime.now().uptimeNanoseconds
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            logger.error(
                "screen capture source configuration failed after "
                    + "\(elapsedMilliseconds(since: configurationStartedAt)) ms"
            )
            throw ScreenCaptureError.displayUnavailable
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier
        let excludedApplications = content.applications.filter { application in
            // 排除当前应用，避免选区遮罩、工具栏和录制控制面板进入成品。
            application.processID == ProcessInfo.processInfo.processIdentifier
                || application.bundleIdentifier == bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let sourceRect = selection.screenCaptureKitSourceFrame
        let outputPixelSize = ScreenCaptureResolutionPolicy.outputPixelSize(
            for: sourceRect.size,
            pointPixelScale: CGFloat(filter.pointPixelScale),
            purpose: purpose
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Int(outputPixelSize.width)
        configuration.height = Int(outputPixelSize.height)
        configuration.showsCursor = true

        logger.info(
            "screen capture source configured in "
                + "\(elapsedMilliseconds(since: configurationStartedAt)) ms"
        )
        return ScreenCaptureSource(filter: filter, configuration: configuration)
    }

    /// 使共享内容缓存失效，后续会话重新读取当前显示器与窗口拓扑。
    func invalidatePreparation() {
        shareableContentCache.invalidate()
    }

    /// 返回当前预热代际共享的可捕获内容快照。
    private func shareableContent() async throws -> SCShareableContent {
        try await shareableContentCache.value()
    }

    /// 显示器排列、尺寸或缩放变化时立即清除缓存，避免沿用旧拓扑。
    @objc private func screenParametersDidChange() {
        shareableContentCache.invalidate()
        logger.info("screen capture source cache invalidated after screen parameters changed")
    }

    /// 使用单调时钟计算阶段耗时。
    private func elapsedMilliseconds(since startedAt: UInt64) -> Int {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        return Int(elapsedNanoseconds / 1_000_000)
    }
}
