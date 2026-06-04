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
}

public struct PermissionSummary: Equatable {
    public var hasAccessibility: Bool
    public var hasInputMonitoring: Bool
    public var hasPostEvent: Bool

    public init(hasAccessibility: Bool, hasInputMonitoring: Bool, hasPostEvent: Bool = false) {
        self.hasAccessibility = hasAccessibility
        self.hasInputMonitoring = hasInputMonitoring
        self.hasPostEvent = hasPostEvent
    }

    public var canUseSuperRightClick: Bool {
        hasAccessibility && hasPostEvent
    }

    public var canPasteAutomatically: Bool {
        hasPostEvent
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
    func requestPostEventPermission() -> Bool
}

public extension PermissionChecking {
    func requestPostEventPermission() -> Bool {
        hasPostEventPermission()
    }
}

public final class PermissionService {
    private let checker: PermissionChecking

    public init(checker: PermissionChecking = SystemPermissionChecker()) {
        self.checker = checker
    }

    public func summary() -> PermissionSummary {
        PermissionSummary(
            hasAccessibility: checker.hasAccessibilityPermission(),
            hasInputMonitoring: checker.hasInputMonitoringPermission(),
            hasPostEvent: checker.hasPostEventPermission()
        )
    }

    public func requestPostEventPermission() -> Bool {
        checker.requestPostEventPermission()
    }

    public func openSystemSettings() {
        openSystemSettings(for: .accessibility)
    }

    public func openSystemSettings(for permission: AppPermission) {
        guard let url = Self.systemSettingsURL(for: permission) else {
            return
        }

        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
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

    public func hasInputMonitoringPermission() -> Bool {
        #if canImport(IOKit)
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
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
}
