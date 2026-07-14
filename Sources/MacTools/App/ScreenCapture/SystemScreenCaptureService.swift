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
}

protocol ScreenStillCapturing {
    func captureStill(for selection: ScreenCaptureSelection) async throws -> CGImage
}

struct ScreenCaptureSource {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
}

final class SystemScreenCaptureService: ScreenStillCapturing {
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
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureError.displayUnavailable
        }

        let excludedApplications: [SCRunningApplication]
        if let bundleIdentifier = Bundle.main.bundleIdentifier,
           let application = content.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            excludedApplications = [application]
        } else {
            excludedApplications = []
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
}
