import Foundation

public struct ClipboardPayload: Equatable {
    public var text: String?
    public var fileURLs: [URL]
    public var imageData: Data?

    public init(text: String? = nil, fileURLs: [URL] = [], imageData: Data? = nil) {
        self.text = text
        self.fileURLs = fileURLs
        self.imageData = imageData
    }
}
