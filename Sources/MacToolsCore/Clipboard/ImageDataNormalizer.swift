// `ImageDataNormalizer` 的剪贴板领域实现。
// 负责载荷分类、内容标识和轮询服务，不管理 AppKit 面板生命周期。

import AppKit
import Foundation

/// 描述 `ImageDataNormalizer` 在剪贴板领域中可取的状态、选项或错误。
enum ImageDataNormalizer {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// 计算并返回 `pngData` 对应的剪贴板领域数据或状态结果。
    static func pngData(from data: Data) -> Data? {
        guard !data.isEmpty else {
            return nil
        }

        if data.starts(with: pngSignature) {
            return data
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        return pngData(from: image)
    }

    /// 计算并返回 `pngData` 对应的剪贴板领域数据或状态结果。
    static func pngData(from image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
