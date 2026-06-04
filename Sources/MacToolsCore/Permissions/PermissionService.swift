import Foundation

#if canImport(ApplicationServices)
import ApplicationServices
#endif

#if canImport(AppKit)
import AppKit
#endif

public enum AppPermission: String, Equatable {
    case accessibility
    case inputMonitoring
}

public struct PermissionSummary: Equatable {
    public var hasAccessibility: Bool
    public var hasInputMonitoring: Bool

    public init(hasAccessibility: Bool, hasInputMonitoring: Bool) {
        self.hasAccessibility = hasAccessibility
        self.hasInputMonitoring = hasInputMonitoring
    }

    public var canUseSuperRightClick: Bool {
        hasAccessibility
    }

    public var missingPermissions: [AppPermission] {
        var permissions: [AppPermission] = []

        if !hasAccessibility {
            permissions.append(.accessibility)
        }

        if !hasInputMonitoring {
            permissions.append(.inputMonitoring)
        }

        return permissions
    }
}

public protocol PermissionChecking {
    func hasAccessibilityPermission() -> Bool
    func hasInputMonitoringPermission() -> Bool
}

public final class PermissionService {
    private let checker: PermissionChecking

    public init(checker: PermissionChecking = SystemPermissionChecker()) {
        self.checker = checker
    }

    public func summary() -> PermissionSummary {
        PermissionSummary(
            hasAccessibility: checker.hasAccessibilityPermission(),
            hasInputMonitoring: checker.hasInputMonitoringPermission()
        )
    }

    public func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }

        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
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
        true
    }
}
