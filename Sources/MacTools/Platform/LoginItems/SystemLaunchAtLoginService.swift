// macOS 登录项服务适配器。
// 负责读取 SMAppService 状态并执行主应用注册、注销和系统设置跳转。

import Combine
import MacToolsCore
import ServiceManagement

/// 在主线程维护系统登录项状态，并向 SwiftUI 发布 Core 可展示快照。
@MainActor
final class SystemLaunchAtLoginService: ObservableObject {
    @Published private(set) var state: LaunchAtLoginSettingsState

    private let statusProvider: @MainActor () -> SMAppService.Status
    private let registerAction: @MainActor () throws -> Void
    private let unregisterAction: @MainActor () throws -> Void
    private let openSystemSettingsAction: @MainActor () -> Void

    convenience init(service: SMAppService = .mainApp) {
        self.init(
            statusProvider: { service.status },
            registerAction: { try service.register() },
            unregisterAction: { try service.unregister() },
            openSystemSettingsAction: SMAppService.openSystemSettingsLoginItems
        )
    }

    /// 注入系统动作以隔离 ServiceManagement，并建立初始状态。
    init(
        statusProvider: @escaping @MainActor () -> SMAppService.Status,
        registerAction: @escaping @MainActor () throws -> Void,
        unregisterAction: @escaping @MainActor () throws -> Void,
        openSystemSettingsAction: @escaping @MainActor () -> Void
    ) {
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
        self.openSystemSettingsAction = openSystemSettingsAction
        self.state = Self.makeState(from: statusProvider())
    }

    /// 重新读取系统状态，兼容用户在“登录项”设置中直接修改选择。
    func refresh() {
        state = Self.makeState(from: statusProvider())
    }

    /// 根据用户选择注册或注销主应用；失败时保留系统实际开关值供重试。
    func setEnabled(_ isEnabled: Bool) {
        let currentStatus = statusProvider()
        do {
            if isEnabled {
                switch currentStatus {
                case .notRegistered:
                    try registerAction()
                case .enabled, .requiresApproval:
                    break
                case .notFound:
                    state = .unavailable
                    return
                @unknown default:
                    state = .unavailable
                    return
                }
            } else {
                switch currentStatus {
                case .enabled, .requiresApproval:
                    try unregisterAction()
                case .notRegistered:
                    break
                case .notFound:
                    state = .unavailable
                    return
                @unknown default:
                    state = .unavailable
                    return
                }
            }
            refresh()
        } catch {
            let statusAfterFailure = statusProvider()
            state = Self.failureState(
                requestedEnabled: isEnabled,
                status: statusAfterFailure,
                errorDescription: error.localizedDescription
            )
        }
    }

    /// 打开 macOS“登录项与扩展”设置，供用户完成系统批准。
    func openSystemSettings() {
        openSystemSettingsAction()
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
            return .unavailable
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
            case .notRegistered:
                return .failed(isEnabled: false, message: "开启失败：\(errorDescription)")
            case .notFound:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        }

        switch status {
        case .notRegistered:
            return .disabled
        case .enabled, .requiresApproval:
            return .failed(isEnabled: true, message: "关闭失败：\(errorDescription)")
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}
