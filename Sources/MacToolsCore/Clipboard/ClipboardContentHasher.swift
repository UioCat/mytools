import CryptoKit
import Foundation

public enum ClipboardContentHasher {
    public static func md5(for payload: ClipboardPayload) -> String? {
        if let firstURL = payload.fileURLs.first {
            return md5String(for: "file:\(firstURL.path)")
        }

        if let imageData = payload.imageData, !imageData.isEmpty {
            return md5String(for: imageData)
        }

        if let text = payload.text, !text.isEmpty {
            return md5String(for: "text:\(text)")
        }

        return nil
    }

    private static func md5String(for text: String) -> String {
        md5String(for: Data(text.utf8))
    }

    private static func md5String(for data: Data) -> String {
        Insecure.MD5.hash(data: data).map { byte in
            String(format: "%02x", byte)
        }.joined()
    }
}
