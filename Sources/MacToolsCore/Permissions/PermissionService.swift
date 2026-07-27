// `PermissionService` 的权限领域实现。
// 负责查询和打开系统权限入口，不直接执行受保护操作。

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

/// 描述 `AppPermission` 在权限领域中可取的状态、选项或错误。
public enum AppPermission: String, Equatable {
    case accessibility
    case inputMonitoring
    case postEvent
    case screenRecording
}

/// 封装 `PermissionSummary` 在权限领域中的值语义和相关操作。
public struct PermissionSummary: Equatable {
    public var hasAccessibility: Bool
    public var hasInputMonitoring: Bool
    public var hasPostEvent: Bool
    public var hasScreenRecording: Bool

    /// 创建 `PermissionSummary`，保存传入依赖并建立初始状态。
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

/// 定义 `PermissionChecking` 在权限领域中需要满足的能力边界。
public protocol PermissionChecking {
    /// 判断 `hasAccessibilityPermission` 所描述的权限领域条件是否成立。
    func hasAccessibilityPermission() -> Bool
    /// 判断 `hasInputMonitoringPermission` 所描述的权限领域条件是否成立。
    func hasInputMonitoringPermission() -> Bool
    /// 判断 `hasPostEventPermission` 所描述的权限领域条件是否成立。
    func hasPostEventPermission() -> Bool
    /// 判断 `hasScreenRecordingPermission` 所描述的权限领域条件是否成立。
    func hasScreenRecordingPermission() -> Bool
    /// 执行 `requestAccessibilityPermission` 对应的权限领域输入输出操作。
    func requestAccessibilityPermission() -> Bool
    /// 执行 `requestInputMonitoringPermission` 对应的权限领域输入输出操作。
    func requestInputMonitoringPermission() -> Bool
    /// 执行 `requestPostEventPermission` 对应的权限领域输入输出操作。
    func requestPostEventPermission() -> Bool
    /// 执行 `requestScreenRecordingPermission` 对应的权限领域输入输出操作。
    func requestScreenRecordingPermission() -> Bool
}

/// 扩展 `PermissionChecking`，补充本文件所需的权限领域能力。
public extension PermissionChecking {
    /// 执行 `requestAccessibilityPermission` 对应的权限领域输入输出操作。
    func requestAccessibilityPermission() -> Bool {
        hasAccessibilityPermission()
    }

    /// 执行 `requestInputMonitoringPermission` 对应的权限领域输入输出操作。
    func requestInputMonitoringPermission() -> Bool {
        hasInputMonitoringPermission()
    }

    /// 执行 `requestPostEventPermission` 对应的权限领域输入输出操作。
    func requestPostEventPermission() -> Bool {
        hasPostEventPermission()
    }

    /// 执行 `requestScreenRecordingPermission` 对应的权限领域输入输出操作。
    func requestScreenRecordingPermission() -> Bool {
        hasScreenRecordingPermission()
    }
}

/// 管理 `PermissionService` 在权限领域中的生命周期、依赖和可变状态。
public final class PermissionService {
    private let checker: PermissionChecking
    private let openSystemSettingsURL: (URL) -> Void

    /// 创建 `PermissionService`，保存传入依赖并建立初始状态。
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

    /// 计算并返回 `summary` 对应的权限领域数据或状态结果。
    public func summary() -> PermissionSummary {
        PermissionSummary(
            hasAccessibility: checker.hasAccessibilityPermission(),
            hasInputMonitoring: checker.hasInputMonitoringPermission(),
            hasPostEvent: checker.hasPostEventPermission(),
            hasScreenRecording: checker.hasScreenRecordingPermission()
        )
    }

    /// 执行 `requestPostEventPermission` 对应的权限领域输入输出操作。
    public func requestPostEventPermission() -> Bool {
        checker.requestPostEventPermission()
    }

    /// 执行 `requestScreenRecordingPermission` 对应的权限领域输入输出操作。
    public func requestScreenRecordingPermission() -> Bool {
        checker.requestScreenRecordingPermission()
    }

    /// 展示 `openSystemSettings` 对应的权限领域界面或系统位置。
    public func openSystemSettings() {
        openSystemSettings(for: .accessibility)
    }

    /// 展示 `openSystemSettings` 对应的权限领域界面或系统位置。
    public func openSystemSettings(for permission: AppPermission) {
        guard let url = Self.systemSettingsURL(for: permission) else {
            return
        }

        openSystemSettingsURL(url)
    }

    /// 执行 `requestPermissionAndOpenSystemSettings` 对应的权限领域输入输出操作。
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

    /// 计算并返回 `systemSettingsURL` 对应的权限领域数据或状态结果。
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

/// 封装 `SystemPermissionChecker` 在权限领域中的值语义和相关操作。
public struct SystemPermissionChecker: PermissionChecking {
    /// 创建 `SystemPermissionChecker`，保存传入依赖并建立初始状态。
    public init() {}

    /// 判断 `hasAccessibilityPermission` 所描述的权限领域条件是否成立。
    public func hasAccessibilityPermission() -> Bool {
        #if canImport(ApplicationServices)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// 执行 `requestAccessibilityPermission` 对应的权限领域输入输出操作。
    public func requestAccessibilityPermission() -> Bool {
        #if canImport(ApplicationServices)
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }

    /// 判断 `hasInputMonitoringPermission` 所描述的权限领域条件是否成立。
    public func hasInputMonitoringPermission() -> Bool {
        #if canImport(IOKit)
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        #else
        return false
        #endif
    }

    /// 执行 `requestInputMonitoringPermission` 对应的权限领域输入输出操作。
    public func requestInputMonitoringPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestListenEventAccess()
        #else
        return false
        #endif
    }

    /// 判断 `hasPostEventPermission` 所描述的权限领域条件是否成立。
    public func hasPostEventPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightPostEventAccess()
        #else
        return false
        #endif
    }

    /// 执行 `requestPostEventPermission` 对应的权限领域输入输出操作。
    public func requestPostEventPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestPostEventAccess()
        #else
        return false
        #endif
    }

    /// 判断 `hasScreenRecordingPermission` 所描述的权限领域条件是否成立。
    public func hasScreenRecordingPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightScreenCaptureAccess()
        #else
        return false
        #endif
    }

    /// 执行 `requestScreenRecordingPermission` 对应的权限领域输入输出操作。
    public func requestScreenRecordingPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestScreenCaptureAccess()
        #else
        return false
        #endif
    }
}
