import AppKit
import Foundation

public protocol PasteboardClient {
    var changeCount: Int { get }
    func readPayload() -> ClipboardPayload
}

public final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public func readPayload() -> ClipboardPayload {
        let text = pasteboard.string(forType: .string)
        let fileURLs = readFileURLs()
        let imageData = readImageData()

        return ClipboardPayload(text: text, fileURLs: fileURLs, imageData: imageData)
    }

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

    private func readFileURLs() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return Self.fileURLs(from: objects)
    }

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
