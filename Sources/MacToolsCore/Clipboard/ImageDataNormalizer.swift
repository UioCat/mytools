import AppKit
import Foundation

enum ImageDataNormalizer {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

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
