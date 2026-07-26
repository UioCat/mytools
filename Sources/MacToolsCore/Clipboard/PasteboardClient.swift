// `PasteboardClient` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import AppKit
import Foundation

/// 定义 `PasteboardClient` 在剪贴板领域中需要满足的能力边界。
public protocol PasteboardClient {
    var changeCount: Int { get }
    /// 读取并返回 `readPayload` 对应的剪贴板领域数据。
    func readPayload() -> ClipboardPayload
}

/// 管理 `SystemPasteboardClient` 在剪贴板领域中的生命周期、依赖和可变状态。
public final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    /// 创建 `SystemPasteboardClient`，保存传入依赖并建立初始状态。
    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    /// 读取并返回 `readPayload` 对应的剪贴板领域数据。
    public func readPayload() -> ClipboardPayload {
        let text = pasteboard.string(forType: .string)
        let fileURLs = readFileURLs()
        let imageData = readImageData()

        return ClipboardPayload(text: text, fileURLs: fileURLs, imageData: imageData)
    }

    /// 计算并返回 `fileURLs` 对应的剪贴板领域数据或状态结果。
    static func fileURLs(from objects: [Any]) -> [URL] {
        objects.compactMap { object in
            let url: URL?

            if let value = object as? URL {
                url = value
            } else if let value = object as? NSURL {
                url = value as URL
            } else {
                url = nil
            }

            guard let url, url.isFileURL else {
                return nil
            }

            return url
        }
    }

    /// 读取并返回 `readFileURLs` 对应的剪贴板领域数据。
    private func readFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return Self.fileURLs(from: objects)
    }

    /// 读取并返回 `readImageData` 对应的剪贴板领域数据。
    private func readImageData() -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return ImageDataNormalizer.pngData(from: pngData)
        }

        if let tiffData = pasteboard.data(forType: .tiff) {
            return ImageDataNormalizer.pngData(from: tiffData)
        }

        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
        return images.first.flatMap(ImageDataNormalizer.pngData)
    }
}
