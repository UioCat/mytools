import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(IOKit)
import IOKit.hid
#endif

#if canImport(AppKit)
import AppKit
#endif

public enum AppPermission: String, Equatable {
    case accessibility
    case inputMonitoring
    case postEvent
    case screenRecording
}

public struct PermissionSummary: Equatable {
    public var hasAccessibility: Bool
    public var hasInputMonitoring: Bool
    public var hasPostEvent: Bool
    public var hasScreenRecording: Bool

    public init(
        hasAccessibility: Bool,
        hasInputMonitoring: Bool,
        hasPostEvent: Bool = false,
        hasScreenRecording: Bool = false
    ) {
        self.hasAccessibility = hasAccessibility
        self.hasInputMonitoring = hasInputMonitoring
        self.hasPostEvent = hasPostEvent
        self.hasScreenRecording = hasScreenRecording
    }

    public var canUseSuperRightClick: Bool {
        hasAccessibility && hasInputMonitoring
    }

    public var firstMissingSuperRightClickPermission: AppPermission? {
        if !hasAccessibility {
            return .accessibility
        }

        if !hasInputMonitoring {
            return .inputMonitoring
        }

        return nil
    }

    public var missingSuperRightClickPermissions: [AppPermission] {
        var permissions: [AppPermission] = []

        if !hasAccessibility {
            permissions.append(.accessibility)
        }

        if !hasInputMonitoring {
            permissions.append(.inputMonitoring)
        }

        return permissions
    }

    public var canPasteAutomatically: Bool {
        hasPostEvent
    }

    public var canCaptureScreen: Bool {
        hasScreenRecording
    }

    public var missingPermissions: [AppPermission] {
        var permissions: [AppPermission] = []

        if !hasAccessibility {
            permissions.append(.accessibility)
        }

        if !hasInputMonitoring {
            permissions.append(.inputMonitoring)
        }

        if !hasPostEvent {
            permissions.append(.postEvent)
        }

        return permissions
    }
}

public protocol PermissionChecking {
    func hasAccessibilityPermission() -> Bool
    func hasInputMonitoringPermission() -> Bool
    func hasPostEventPermission() -> Bool
    func hasScreenRecordingPermission() -> Bool
    func requestAccessibilityPermission() -> Bool
    func requestInputMonitoringPermission() -> Bool
    func requestPostEventPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
}

public extension PermissionChecking {
    func requestAccessibilityPermission() -> Bool {
        hasAccessibilityPermission()
    }

    func requestInputMonitoringPermission() -> Bool {
        hasInputMonitoringPermission()
    }

    func requestPostEventPermission() -> Bool {
        hasPostEventPermission()
    }

    func requestScreenRecordingPermission() -> Bool {
        hasScreenRecordingPermission()
    }
}

public final class PermissionService {
    private let checker: PermissionChecking
    private let openSystemSettingsURL: (URL) -> Void

    public init(
        checker: PermissionChecking = SystemPermissionChecker(),
        openSystemSettingsURL: ((URL) -> Void)? = nil
    ) {
        self.checker = checker
        self.openSystemSettingsURL = openSystemSettingsURL ?? { url in
            #if canImport(AppKit)
            _ = NSWorkspace.shared.open(url)
            #endif
        }
    }

    public func summary() -> PermissionSummary {
        PermissionSummary(
            hasAccessibility: checker.hasAccessibilityPermission(),
            hasInputMonitoring: checker.hasInputMonitoringPermission(),
            hasPostEvent: checker.hasPostEventPermission(),
            hasScreenRecording: checker.hasScreenRecordingPermission()
        )
    }

    public func requestPostEventPermission() -> Bool {
        checker.requestPostEventPermission()
    }

    public func requestScreenRecordingPermission() -> Bool {
        checker.requestScreenRecordingPermission()
    }

    public func requestSuperRightClickPermissions() -> PermissionSummary {
        let currentSummary = summary()

        if !currentSummary.hasAccessibility {
            _ = checker.requestAccessibilityPermission()
        }

        if !currentSummary.hasInputMonitoring {
            _ = checker.requestInputMonitoringPermission()
        }

        return summary()
    }

    public func openSystemSettings() {
        openSystemSettings(for: .accessibility)
    }

    public func openSystemSettings(for permission: AppPermission) {
        guard let url = Self.systemSettingsURL(for: permission) else {
            return
        }

        openSystemSettingsURL(url)
    }

    public func requestPermissionAndOpenSystemSettings(for permission: AppPermission) {
        switch permission {
        case .accessibility:
            _ = checker.requestAccessibilityPermission()
        case .inputMonitoring:
            _ = checker.requestInputMonitoringPermission()
        case .postEvent:
            _ = checker.requestPostEventPermission()
        case .screenRecording:
            _ = checker.requestScreenRecordingPermission()
        }

        openSystemSettings(for: permission)
    }

    public static func systemSettingsURL(for permission: AppPermission) -> URL? {
        switch permission {
        case .accessibility:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        case .inputMonitoring:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
        case .postEvent:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        case .screenRecording:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
        }
    }
}

public struct SystemPermissionChecker: PermissionChecking {
    public init() {}

    public func hasAccessibilityPermission() -> Bool {
        #if canImport(ApplicationServices)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    public func requestAccessibilityPermission() -> Bool {
        #if canImport(ApplicationServices)
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }

    public func hasInputMonitoringPermission() -> Bool {
        #if canImport(IOKit)
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        #else
        return false
        #endif
    }

    public func requestInputMonitoringPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestListenEventAccess()
        #else
        return false
        #endif
    }

    public func hasPostEventPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightPostEventAccess()
        #else
        return false
        #endif
    }

    public func requestPostEventPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestPostEventAccess()
        #else
        return false
        #endif
    }

    public func hasScreenRecordingPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightScreenCaptureAccess()
        #else
        return false
        #endif
    }

    public func requestScreenRecordingPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestScreenCaptureAccess()
        #else
        return false
        #endif
    }
}
