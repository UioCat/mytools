// `ClipboardPayload` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import Foundation

/// 封装 `ClipboardPayload` 在剪贴板领域中的值语义和相关操作。
public struct ClipboardPayload: Equatable, Sendable {
    public var text: String?
    public var fileURLs: [URL]
    public var imageData: Data?

    /// 创建 `ClipboardPayload`，保存传入依赖并建立初始状态。
    public init(text: String? = nil, fileURLs: [URL] = [], imageData: Data? = nil) {
        self.text = text
        self.fileURLs = fileURLs
        self.imageData = imageData
    }
}
