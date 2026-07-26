// `ClipboardContentHasher` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import CryptoKit
import Foundation

/// 描述 `ClipboardContentHasher` 在剪贴板领域中可取的状态、选项或错误。
public enum ClipboardContentHasher {
    /// 计算并返回 `sha256` 对应的剪贴板领域数据或状态结果。
    public static func sha256(for payload: ClipboardPayload) -> String? {
        if let firstURL = payload.fileURLs.first {
            return sha256String(for: "file:\(firstURL.standardizedFileURL.path)")
        }

        if let text = payload.text, !text.isEmpty {
            return sha256String(for: "text:\(text)")
        }

        if let imageData = payload.imageData, !imageData.isEmpty {
            return sha256String(for: imageData)
        }

        return nil
    }

    /// 计算并返回 `sha256String` 对应的剪贴板领域数据或状态结果。
    public static func sha256String(for data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    /// 计算并返回 `sha256String` 对应的剪贴板领域数据或状态结果。
    private static func sha256String(for text: String) -> String {
        sha256String(for: Data(text.utf8))
    }
}
