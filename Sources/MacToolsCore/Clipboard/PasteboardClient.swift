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
        let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)

        return ClipboardPayload(text: text, fileURLs: fileURLs, imageData: imageData)
    }

    private func readFileURLs() -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        return objects.compactMap { object in
            if let url = object as? URL {
                return url
            }
            if let url = object as? NSURL {
                return url as URL
            }
            return nil
        }
    }
}
