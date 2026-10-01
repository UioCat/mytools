// 合成预览状态与打包应用验证入口。
import AppKit
import Foundation
import MacToolsCore

extension AppEnvironment {
    /// 注入不含真实账户数据的确定性预览状态，并打开设置页供 UI 验证。
    func openSettingsForUIVerification() {
        var previewSettings = settings
        previewSettings.sync = SyncSettings(
            isEnabled: true,
            clipboardScope: .allHistory,
            storageLimit: .megabytes512
        )
        syncModel.folderPath = "/Users/example/iCloud Drive/MacTools Sync"
        syncModel.folderIsUbiquitous = true
        syncModel.status = .synced(
            lastSyncAt: Date(),
            usage: SyncStorageUsage(
                usedBytes: 187 * 1_024 * 1_024,
                capacityBytes: SyncStorageLimit.megabytes512.byteLimit,
                ordinaryHistoryCount: 328,
                imageBytes: 180 * 1_024 * 1_024,
                textBytes: 2 * 1_024 * 1_024,
                metadataBytes: 5 * 1_024 * 1_024
            )
        )
        syncModel.devices = [
            SyncDeviceSummary(
                id: "verification-current",
                name: "MacBook Pro",
                isCurrentDevice: true,
                lastUpdatedAt: Date()
            ),
            SyncDeviceSummary(
                id: "verification-peer",
                name: "Mac Studio",
                isCurrentDevice: false,
                lastUpdatedAt: Date().addingTimeInterval(-3_600)
            )
        ]
        syncModel.remoteSettings = previewSettings
        openSettings()
        mainPanel.resize(to: NSSize(width: 980, height: 900))
    }

    /// 供发布验收从较低构建号启动一次真实的 Sparkle 更新检查。
    func checkForUpdatesForUIVerification() {
        softwareUpdateService.checkForUpdates()
    }
}
