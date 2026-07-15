import AppKit
import CoreGraphics
import MacToolsCore
import ScreenCaptureKit

enum ScreenCaptureError: Error, Equatable {
    case displayUnavailable
    case captureAlreadyRunning
    case recorderNotRunning
    case writerCreationFailed
    case writerFailed
    case downloadsDirectoryUnavailable
    case editorPresentationFailed
}

@MainActor
protocol ScreenStillCapturing {
    func prepare() async throws
    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage
    func invalidatePreparation()
}

extension ScreenStillCapturing {
    func prepare() async throws {}
    func invalidatePreparation() {}
}

struct ScreenCaptureSource {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
}

@MainActor
final class SystemScreenCaptureService: ScreenStillCapturing {
    private let shareableContentCache = ScreenCapturePreparationCache<SCShareableContent> {
        try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
    }

    func prepare() async throws {
        _ = try await shareableContent()
    }

    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage {
        let source = try await source(for: selection, purpose: .screenshot)
        return try await SCScreenshotManager.captureImage(
            contentFilter: source.filter,
            configuration: source.configuration
        )
    }

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
            application.processID == ProcessInfo.processInfo.processIdentifier
                || application.bundleIdentifier == bundleIdentifier
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let sourceRect = selection.displayRelativeFrame
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

    func invalidatePreparation() {
        shareableContentCache.invalidate()
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await shareableContentCache.value()
    }
}
