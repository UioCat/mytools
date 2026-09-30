// macOS 登录项服务适配器。
// 负责读取 SMAppService 状态并执行主应用注册、注销和系统设置跳转。

import Combine
import Foundation
import MacToolsCore
import ServiceManagement

/// 在主线程维护系统登录项状态，并向 SwiftUI 发布 Core 可展示快照。
@MainActor
final class SystemLaunchAtLoginService: ObservableObject {
    @Published private(set) var state: LaunchAtLoginSettingsState

    private let applicationIsSupported: @MainActor () -> Bool
    private let statusProvider: @MainActor () -> SMAppService.Status
    private let registerAction: @MainActor () throws -> Void
    private let unregisterAction: @MainActor () throws -> Void
    private let openSystemSettingsAction: @MainActor () -> Void

    convenience init(service: SMAppService = .mainApp, bundle: Bundle = .main) {
        self.init(
            applicationIsSupported: {
                Self.supportsMainAppLoginItem(
                    bundleURL: bundle.bundleURL,
                    bundleIdentifier: bundle.bundleIdentifier,
                    executableURL: bundle.executableURL,
                    packageType: bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String
                )
            },
            statusProvider: { service.status },
            registerAction: { try service.register() },
            unregisterAction: { try service.unregister() },
            openSystemSettingsAction: SMAppService.openSystemSettingsLoginItems
        )
    }

    /// 注入系统动作以隔离 ServiceManagement，并建立初始状态。
    init(
        applicationIsSupported: @escaping @MainActor () -> Bool,
        statusProvider: @escaping @MainActor () -> SMAppService.Status,
        registerAction: @escaping @MainActor () throws -> Void,
        unregisterAction: @escaping @MainActor () throws -> Void,
        openSystemSettingsAction: @escaping @MainActor () -> Void
    ) {
        self.applicationIsSupported = applicationIsSupported
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
        self.openSystemSettingsAction = openSystemSettingsAction
        self.state = applicationIsSupported()
            ? Self.makeState(from: statusProvider())
            : .requiresAppBundle
    }

    /// 重新读取系统状态，兼容用户在“登录项”设置中直接修改选择。
    func refresh() {
        state = applicationIsSupported()
            ? Self.makeState(from: statusProvider())
            : .requiresAppBundle
    }

    /// 根据用户选择注册或注销主应用；失败时保留系统实际开关值供重试。
    func setEnabled(_ isEnabled: Bool) {
        guard applicationIsSupported() else {
            state = .requiresAppBundle
            return
        }
        let currentStatus = statusProvider()
        do {
            if isEnabled {
                switch currentStatus {
                case .notRegistered, .notFound:
                    // 新安装的有效应用也可能返回 notFound；注册结果才决定是否可用。
                    try registerAction()
                case .enabled, .requiresApproval:
                    break
                @unknown default:
                    state = .unavailable
                    return
                }
            } else {
                switch currentStatus {
                case .enabled, .requiresApproval:
                    try unregisterAction()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    state = .unavailable
                    return
                }
            }
            refresh()
            if isEnabled && (state == .disabled || state == .registrationMissing) {
                state = .failed(isEnabled: false, message: "未确认登录项注册，请重试或在系统设置中检查")
            }
        } catch {
            let statusAfterFailure = statusProvider()
            state = Self.failureState(
                requestedEnabled: isEnabled,
                status: statusAfterFailure,
                errorDescription: Self.errorDescription(for: error)
            )
        }
    }

    /// 打开 macOS“登录项与扩展”设置，供用户完成系统批准。
    func openSystemSettings() {
        openSystemSettingsAction()
    }

    /// 仅接受包含主程序身份的应用包；签名及系统批准由 register() 验证。
    static func supportsMainAppLoginItem(
        bundleURL: URL,
        bundleIdentifier: String?,
        executableURL: URL?,
        packageType: String?
    ) -> Bool {
        guard bundleURL.pathExtension.lowercased() == "app",
              packageType == "APPL",
              let bundleIdentifier,
              !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let executableURL else {
            return false
        }
        // URL 的目录尾斜杠元数据可能不同；比较规范化路径避免误拒绝同一目录。
        return executableURL.deletingLastPathComponent().standardizedFileURL.path
            == bundleURL.appendingPathComponent("Contents/MacOS").standardizedFileURL.path
    }

    private static func errorDescription(for error: Error) -> String {
        let systemError = error as NSError
        if systemError.domain == SMAppServiceErrorDomain {
            switch systemError.code {
            case Int(kSMErrorInvalidSignature):
                return "macOS 无法验证应用签名，请重新安装完整的 MacTools.app"
            case Int(kSMErrorToolNotValid):
                return "macOS 未找到完整的应用，请重新安装 MacTools.app"
            case Int(kSMErrorLaunchDeniedByUser):
                return "请在系统设置的登录项中允许 MacTools"
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func makeState(from status: SMAppService.Status) -> LaunchAtLoginSettingsState {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .registrationMissing
        @unknown default:
            return .unavailable
        }
    }

    /// 以用户请求和失败后的系统事实共同决定恢复状态，避免提供相反操作。
    private static func failureState(
        requestedEnabled: Bool,
        status: SMAppService.Status,
        errorDescription: String
    ) -> LaunchAtLoginSettingsState {
        if requestedEnabled {
            switch status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered, .notFound:
                return .failed(isEnabled: false, message: "开启失败：\(errorDescription)")
            @unknown default:
                return .unavailable
            }
        }

        switch status {
        case .notRegistered:
            return .disabled
        case .enabled, .requiresApproval, .notFound:
            return .failed(isEnabled: true, message: "关闭失败：\(errorDescription)")
        @unknown default:
            return .unavailable
        }
    }
}
