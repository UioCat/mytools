import CryptoKit
import Foundation

public enum ClipboardContentHasher {
    public static func sha256(for payload: ClipboardPayload) -> String? {
        if let firstURL = payload.fileURLs.first {
            return sha256String(for: "file:\(firstURL.standardizedFileURL.path)")
        }

        if let imageData = payload.imageData, !imageData.isEmpty {
            return sha256String(for: imageData)
        }

        if let text = payload.text, !text.isEmpty {
            return sha256String(for: "text:\(text)")
        }

        return nil
    }

    public static func sha256String(for data: Data) -> String {
        SHA256.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }

    private static func sha256String(for text: String) -> String {
        sha256String(for: Data(text.utf8))
    }
}
