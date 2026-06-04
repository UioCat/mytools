import XCTest
@testable import MacToolsCore

final class ClipboardClassifierTests: XCTestCase {
    func testClassifiesPlainText() {
        let item = ClipboardClassifier().classify(
            payload: ClipboardPayload(text: "hello world"),
            sourceApp: "Notes"
        )

        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.displayTitle, "hello world")
        XCTAssertEqual(item.searchableText, "hello world")
        XCTAssertEqual(item.text, "hello world")
        XCTAssertEqual(item.sourceApp, "Notes")
        XCTAssertNil(item.originalPath)
        XCTAssertNil(item.cachedFilePath)
        XCTAssertNil(item.thumbnailPath)
        XCTAssertNil(item.lastUsedAt)
        XCTAssertEqual(item.useCount, 0)
        XCTAssertFalse(item.isPinned)
        XCTAssertFalse(item.isFavorite)
    }

    func testClassifiesURLTextByScheme() {
        let longURL = "https://example.com/" + String(repeating: "a", count: 90)

        let item = ClipboardClassifier().classify(
            payload: ClipboardPayload(text: longURL),
            sourceApp: nil
        )

        XCTAssertEqual(item.kind, .url)
        XCTAssertEqual(item.displayTitle, String(longURL.prefix(80)))
        XCTAssertEqual(item.searchableText, longURL)
        XCTAssertEqual(item.text, longURL)
    }

    func testClassifiesFolderPath() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }

        let item = ClipboardClassifier().classify(
            payload: ClipboardPayload(fileURLs: [folderURL]),
            sourceApp: "Finder"
        )

        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.displayTitle, folderURL.lastPathComponent)
        XCTAssertEqual(item.searchableText, folderURL.path)
        XCTAssertEqual(item.originalPath, folderURL.path)
        XCTAssertNil(item.text)
    }

    func testClassifiesImageFileByExtension() throws {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("JPG")
        try Data([0xFF, 0xD8]).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let item = ClipboardClassifier().classify(
            payload: ClipboardPayload(fileURLs: [imageURL]),
            sourceApp: "Finder"
        )

        XCTAssertEqual(item.kind, .imageFile)
        XCTAssertEqual(item.displayTitle, imageURL.lastPathComponent)
        XCTAssertEqual(item.originalPath, imageURL.path)
    }

    func testClassifiesRegularFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        try Data("notes".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let item = ClipboardClassifier().classify(
            payload: ClipboardPayload(fileURLs: [fileURL]),
            sourceApp: "Finder"
        )

        XCTAssertEqual(item.kind, .file)
        XCTAssertEqual(item.displayTitle, fileURL.lastPathComponent)
        XCTAssertEqual(item.originalPath, fileURL.path)
    }

    func testClassifiesRawImageData() {
        let item = ClipboardClassifier().classify(
            payload: ClipboardPayload(imageData: Data([0x89, 0x50, 0x4E, 0x47])),
            sourceApp: "Preview"
        )

        XCTAssertEqual(item.kind, .imageData)
        XCTAssertEqual(item.displayTitle, "Image from Preview")
        XCTAssertEqual(item.searchableText, "Preview")
        XCTAssertNil(item.text)
        XCTAssertNil(item.originalPath)
    }

    func testClassifiesEmptyPayloadAsUnknown() {
        let before = Date()

        let item = ClipboardClassifier().classify(payload: ClipboardPayload(), sourceApp: nil)

        XCTAssertEqual(item.kind, .unknown)
        XCTAssertEqual(item.displayTitle, "Unknown clipboard item")
        XCTAssertEqual(item.searchableText, "")
        XCTAssertGreaterThanOrEqual(item.createdAt, before)
        XCTAssertNil(item.lastUsedAt)
        XCTAssertEqual(item.useCount, 0)
        XCTAssertFalse(item.isPinned)
        XCTAssertFalse(item.isFavorite)
    }
}
