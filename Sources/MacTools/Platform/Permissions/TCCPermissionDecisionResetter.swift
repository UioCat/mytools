// macOS TCC 权限决定清理适配器。
// 仅按当前应用 Bundle ID 调用系统 tccutil，不影响其他应用。

import Foundation
import MacToolsCore

/// 在后台执行 tccutil，避免等待系统命令时阻塞主线程。
struct TCCPermissionDecisionResetter: PermissionDecisionResetting {
    func resetAllDecisions(for bundleIdentifier: String) async throws {
        let result = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardError = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "All", bundleIdentifier]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = standardError

            do {
                try process.run()
            } catch {
                throw PermissionDecisionResetError.commandFailed(
                    exitCode: -1,
                    message: "无法启动系统权限清理命令：\(error.localizedDescription)"
                )
            }

            process.waitUntilExit()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, message)
        }.value

        guard result.0 == 0 else {
            throw PermissionDecisionResetError.commandFailed(
                exitCode: result.0,
                message: result.1
            )
        }
    }
}
