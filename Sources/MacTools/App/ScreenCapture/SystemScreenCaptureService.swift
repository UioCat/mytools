// `SystemScreenCaptureService` 的屏幕捕获系统集成实现。
// 负责选区、截图、标注和录屏生命周期，不承载可复用的纯业务模型。

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
final class SystemScreenCaptureService: ScreenStillCapturing {
    private let shareableContentCache = ScreenCapturePreparationCache<SCShareableContent> {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
    }

    /// 异步安排或刷新 `prepare` 对应的屏幕捕获系统集成工作。
    func prepare() async throws {
        _ = try await shareableContent()
    }

    /// 捕获指定区域的静态图像。
    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage {
        let source = try await source(for: selection, purpose: .screenshot)
        return try await SCScreenshotManager.captureImage(
            contentFilter: source.filter,
            configuration: source.configuration
        )
    }

    /// 将全局选区转换为 ScreenCaptureKit 源区域，并按截图或录屏策略计算输出分辨率。
    func source(
        for selection: ScreenCaptureSelection,
        purpose: ScreenCaptureMode
    ) async throws -> ScreenCaptureSource {
        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
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
}
