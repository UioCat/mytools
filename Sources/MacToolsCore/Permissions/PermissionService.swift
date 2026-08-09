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
    /// 查询当前进程是否已经获得辅助功能信任。
    func hasAccessibilityPermission() -> Bool
    /// 查询当前进程是否可以监听全局输入事件。
    func hasInputMonitoringPermission() -> Bool
    /// 查询当前进程是否可以向其他应用发送键盘事件。
    func hasPostEventPermission() -> Bool
    /// 查询当前进程是否可以读取屏幕像素。
    func hasScreenRecordingPermission() -> Bool
    /// 请求辅助功能权限并返回调用后的即时授权状态。
    func requestAccessibilityPermission() -> Bool
    /// 请求输入监控权限并返回系统 API 的即时结果。
    func requestInputMonitoringPermission() -> Bool
    /// 请求事件发送权限并返回系统 API 的即时结果。
    func requestPostEventPermission() -> Bool
    /// 请求屏幕录制权限并返回系统 API 的即时结果。
    func requestScreenRecordingPermission() -> Bool
}

/// 描述清理当前应用 TCC 授权决定时可能发生的错误。
public enum PermissionDecisionResetError: LocalizedError, Equatable, Sendable {
    case missingBundleIdentifier
    case unavailable
    case commandFailed(exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "无法识别当前 MacTools 应用标识。"
        case .unavailable:
            return "当前环境不支持清理系统权限记录。"
        case let .commandFailed(_, message):
            return message.isEmpty ? "系统未能清理 MacTools 的权限记录。" : message
        }
    }
}

/// 隔离 TCC 命令执行，使权限领域不直接依赖系统进程 API。
public protocol PermissionDecisionResetting: Sendable {
    func resetAllDecisions(for bundleIdentifier: String) async throws
}

/// 在未注入 macOS 平台实现时提供明确失败，而不是静默假装清理成功。
public struct UnavailablePermissionDecisionResetter: PermissionDecisionResetting {
    public init() {}

    public func resetAllDecisions(for bundleIdentifier: String) async throws {
        throw PermissionDecisionResetError.unavailable
    }
}

/// 扩展 `PermissionChecking`，补充本文件所需的权限领域能力。
public extension PermissionChecking {
    /// 未提供请求实现时退化为只读辅助功能状态检查。
    func requestAccessibilityPermission() -> Bool {
        hasAccessibilityPermission()
    }

    /// 未提供请求实现时退化为只读输入监控状态检查。
    func requestInputMonitoringPermission() -> Bool {
        hasInputMonitoringPermission()
    }

    /// 未提供请求实现时退化为只读事件发送状态检查。
    func requestPostEventPermission() -> Bool {
        hasPostEventPermission()
    }

    /// 未提供请求实现时退化为只读屏幕录制状态检查。
    func requestScreenRecordingPermission() -> Bool {
        hasScreenRecordingPermission()
    }
}

/// 管理 `PermissionService` 在权限领域中的生命周期、依赖和可变状态。
public final class PermissionService {
    private let checker: PermissionChecking
    private let decisionResetter: any PermissionDecisionResetting
    private let bundleIdentifierProvider: () -> String?
    private let openSystemSettingsURL: (URL) -> Void

    /// 创建 `PermissionService`，保存传入依赖并建立初始状态。
    public init(
        checker: PermissionChecking = SystemPermissionChecker(),
        decisionResetter: any PermissionDecisionResetting = UnavailablePermissionDecisionResetter(),
        bundleIdentifierProvider: @escaping () -> String? = { Bundle.main.bundleIdentifier },
        openSystemSettingsURL: ((URL) -> Void)? = nil
    ) {
        self.checker = checker
        self.decisionResetter = decisionResetter
        self.bundleIdentifierProvider = bundleIdentifierProvider
        self.openSystemSettingsURL = openSystemSettingsURL ?? { url in
            #if canImport(AppKit)
            _ = NSWorkspace.shared.open(url)
            #endif
        }
    }

    /// 在同一次调用中读取四项 TCC 能力，形成供 UI 和功能预检使用的快照。
    public func summary() -> PermissionSummary {
        PermissionSummary(
            hasAccessibility: checker.hasAccessibilityPermission(),
            hasInputMonitoring: checker.hasInputMonitoringPermission(),
            hasPostEvent: checker.hasPostEventPermission(),
            hasScreenRecording: checker.hasScreenRecordingPermission()
        )
    }

    /// 请求自动粘贴所需的事件发送权限。
    public func requestPostEventPermission() -> Bool {
        checker.requestPostEventPermission()
    }

    /// 请求截图录屏所需的屏幕读取权限。
    public func requestScreenRecordingPermission() -> Bool {
        checker.requestScreenRecordingPermission()
    }

    /// 只清理当前 Bundle ID 的 TCC 决定，供签名身份迁移后一次性重新授权。
    public func resetPermissionDecisions() async throws {
        guard let bundleIdentifier = bundleIdentifierProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty
        else {
            throw PermissionDecisionResetError.missingBundleIdentifier
        }

        try await decisionResetter.resetAllDecisions(for: bundleIdentifier)
    }

    /// 为兼容旧调用默认打开辅助功能隐私设置。
    public func openSystemSettings() {
        openSystemSettings(for: .accessibility)
    }

    /// 打开指定能力对应的系统隐私设置；无法构造 URL 时保持静默。
    public func openSystemSettings(for permission: AppPermission) {
        guard let url = Self.systemSettingsURL(for: permission) else {
            return
        }

        openSystemSettingsURL(url)
    }

    /// 先触发系统授权请求，再打开对应设置页供用户确认或修改。
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

    /// 将功能权限映射到 macOS 隐私设置的深链接。
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

    /// 使用 AX 信任状态查询辅助功能授权，不触发系统弹窗。
    public func hasAccessibilityPermission() -> Bool {
        #if canImport(ApplicationServices)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// 使用带 Prompt 选项的 AX 查询触发辅助功能授权提示。
    public func requestAccessibilityPermission() -> Bool {
        #if canImport(ApplicationServices)
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
        #else
        return false
        #endif
    }

    /// 通过 IOKit 查询全局输入监听授权，不触发提示。
    public func hasInputMonitoringPermission() -> Bool {
        #if canImport(IOKit)
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        #else
        return false
        #endif
    }

    /// 调用 CoreGraphics 请求全局输入监听权限。
    public func requestInputMonitoringPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestListenEventAccess()
        #else
        return false
        #endif
    }

    /// 预检向其他应用投递键盘事件的授权状态。
    public func hasPostEventPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightPostEventAccess()
        #else
        return false
        #endif
    }

    /// 请求向其他应用投递键盘事件的权限。
    public func requestPostEventPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestPostEventAccess()
        #else
        return false
        #endif
    }

    /// 预检 ScreenCaptureKit 读取屏幕像素所需授权。
    public func hasScreenRecordingPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGPreflightScreenCaptureAccess()
        #else
        return false
        #endif
    }

    /// 请求屏幕录制权限；用户决定通常需要在后续调用中重新查询。
    public func requestScreenRecordingPermission() -> Bool {
        #if canImport(CoreGraphics)
        return CGRequestScreenCaptureAccess()
        #else
        return false
        #endif
    }
}
