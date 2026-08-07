// `PasteboardClient` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import AppKit
import Foundation

/// 定义 `PasteboardClient` 在剪贴板领域中需要满足的能力边界。
public protocol PasteboardClient {
    var changeCount: Int { get }
    /// 读取并返回 `readPayload` 对应的剪贴板领域数据。
    func readPayload() -> ClipboardPayload
    /// 读取适合立即排队的原始载荷，避免在高频采样阶段执行图片转码。
    func readSnapshotPayload() -> ClipboardPayload
}

public extension PasteboardClient {
    /// 自定义客户端默认复用完整读取；系统客户端覆盖此方法以延后图片转码。
    func readSnapshotPayload() -> ClipboardPayload {
        readPayload()
    }
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
        let payload = readSnapshotPayload()
        let imageData = payload.imageData.flatMap(ImageDataNormalizer.pngData)
        return ClipboardPayload(
            text: payload.text,
            fileURLs: payload.fileURLs,
            imageData: imageData
        )
    }

    /// 只复制分类所需的原始数据；文本或文件存在时不再读取不会参与分类的图片表示。
    public func readSnapshotPayload() -> ClipboardPayload {
        let text = pasteboard.string(forType: .string)
        let fileURLs = readFileURLs()
        let hasPreferredContent = !fileURLs.isEmpty || !(text?.isEmpty ?? true)
        let imageData = hasPreferredContent ? nil : readRawImageData()

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

    /// 优先复制剪贴板已有的图片字节；只有缺少 PNG/TIFF 表示时才读取 `NSImage`。
    private func readRawImageData() -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff) {
            return tiffData
        }

        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] ?? []
        return images.first?.tiffRepresentation
    }
}
