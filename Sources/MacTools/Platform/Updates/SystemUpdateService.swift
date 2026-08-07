// Sparkle 软件更新适配器。
// 负责把平台更新器状态转换为 Core 可展示快照，并执行用户发起的更新操作。

import Combine
import Foundation
import MacToolsCore
import Sparkle

/// 在主线程持有 Sparkle 控制器，并向 SwiftUI 运行时发布最新设置状态。
@MainActor
final class SystemUpdateService: ObservableObject {
    @Published private(set) var state: SoftwareUpdateSettingsState

    private let updaterController: SPUStandardUpdaterController
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    init(bundle: Bundle = .main) {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = updaterController.updater

        self.updaterController = updaterController
        self.state = Self.makeState(bundle: bundle, updater: updater)
        self.canCheckForUpdatesObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor [weak self] in
                self?.refreshState(bundle: bundle, updater: updater)
            }
        }
    }

    /// 启动带标准界面的用户主动更新检查。
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// 只在用户切换开关时更新 Sparkle 自带偏好，避免覆盖既有设备选择。
    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = isEnabled
        refreshState(bundle: .main, updater: updaterController.updater)
    }

    /// 只在用户切换开关时允许或禁止 Sparkle 后台准备与安装更新。
    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = isEnabled
        refreshState(bundle: .main, updater: updaterController.updater)
    }

    private func refreshState(bundle: Bundle, updater: SPUUpdater) {
        state = Self.makeState(bundle: bundle, updater: updater)
    }

    private static func makeState(
        bundle: Bundle,
        updater: SPUUpdater
    ) -> SoftwareUpdateSettingsState {
        SoftwareUpdateSettingsState(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            canCheckForUpdates: updater.canCheckForUpdates,
            automaticallyChecksForUpdates: updater.automaticallyChecksForUpdates,
            automaticallyDownloadsUpdates: updater.automaticallyDownloadsUpdates
        )
    }
}
