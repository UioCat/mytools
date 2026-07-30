import AppKit
import Foundation
import XCTest
@testable import MacToolsCore

final class PasteActionServiceTests: XCTestCase {
    func testPrepareImageContentReturnsNormalizedPNG() throws {
        let tiffURL = try temporaryImageURL(data: try makeTIFFImageData())
        defer { try? FileManager.default.removeItem(at: tiffURL.deletingLastPathComponent()) }

        let content = try PasteActionService.prepareContent(
            for: .testItem(kind: .imageData, cachedFilePath: tiffURL.path)
        )

        guard case let .png(data) = content else {
            return XCTFail("expected prepared PNG")
        }
        XCTAssertEqual(
            data.prefix(8),
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )
    }

    func testWritePreparedPNGDoesNotReadOrNormalizeTheSourceAgain() throws {
        let pasteboard = FakeWritablePasteboard()
        let service = PasteActionService(
            pasteboard: pasteboard,
            eventSender: FakePasteEventSender()
        )
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        try service.write(.png(png))

        XCTAssertEqual(pasteboard.operations, [.writeImageData(png)])
    }

    func testPrepareImageContentMapsUnreadableSourceToInvalidImageData() {
        let item = ClipboardItem.testItem(
            kind: .imageData,
            cachedFilePath: "/tmp/MacToolsTests-\(UUID().uuidString)/missing.tiff"
        )

        XCTAssertThrowsError(try PasteActionService.prepareContent(for: item)) { error in
            XCTAssertEqual(error as? PasteActionError, .invalidImageData)
        }
    }

    func testCopyOnlyWritesTextToPasteboard() throws {
        let pasteboard = FakeWritablePasteboard()
        let sender = FakePasteEventSender()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: sender)

        try service.copy(.testItem(text: "hello"))

        XCTAssertEqual(pasteboard.writtenText, "hello")
        XCTAssertNil(pasteboard.writtenFileURL)
        XCTAssertFalse(sender.didSendPaste)
        XCTAssertFalse(sender.didSendCopy)
    }

    func testCopyWritesOriginalPathAsFileURLWhenTextIsMissing() throws {
        let pasteboard = FakeWritablePasteboard()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: FakePasteEventSender())

        try service.copy(.testItem(kind: .file, originalPath: "/tmp/document.txt"))

        XCTAssertEqual(pasteboard.writtenFileURL, URL(fileURLWithPath: "/tmp/document.txt"))
        XCTAssertNil(pasteboard.writtenText)
    }

    func testCopyFallsBackToCachedFilePathWhenOriginalPathIsMissing() throws {
        let pasteboard = FakeWritablePasteboard()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: FakePasteEventSender())

        try service.copy(.testItem(kind: .imageFile, cachedFilePath: "/tmp/cached-image.png"))

        XCTAssertEqual(pasteboard.writtenFileURL, URL(fileURLWithPath: "/tmp/cached-image.png"))
        XCTAssertNil(pasteboard.writtenText)
    }

    func testCopyImageDataWritesNormalizedPNGInsteadOfFileURL() throws {
        let cachedImageURL = try temporaryImageURL(data: try makeTIFFImageData())
        defer { try? FileManager.default.removeItem(at: cachedImageURL.deletingLastPathComponent()) }
        let pasteboard = FakeWritablePasteboard()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: FakePasteEventSender())

        try service.copy(.testItem(kind: .imageData, cachedFilePath: cachedImageURL.path))

        guard case let .writeImageData(data) = pasteboard.operations.first else {
            return XCTFail("expected normalized PNG data")
        }
        XCTAssertEqual(
            data.prefix(8),
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )
    }

    func testCopyThrowsUnsupportedItemWhenNoRestorableContentExists() {
        let pasteboard = FakeWritablePasteboard()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: FakePasteEventSender())

        XCTAssertThrowsError(try service.copy(.testItem(kind: .unknown))) { error in
            XCTAssertEqual(error as? PasteActionError, .unsupportedItem)
        }
        XCTAssertTrue(pasteboard.operations.isEmpty)
    }

    func testCopyAndPasteWritesTextThenSendsPasteEvent() throws {
        let pasteboard = FakeWritablePasteboard()
        let sender = FakePasteEventSender()
        let service = PasteActionService(pasteboard: pasteboard, eventSender: sender)

        try service.copyAndPaste(.testItem(text: "hello"))

        XCTAssertEqual(pasteboard.operations, [.writeText("hello")])
        XCTAssertTrue(sender.didSendPaste)
        XCTAssertFalse(sender.didSendCopy)
        XCTAssertEqual(sender.sendPasteCount, 1)
    }
}

private final class FakeWritablePasteboard: WritablePasteboard {
    enum Operation: Equatable {
        case writeText(String)
        case writeFileURL(URL)
        case writeImageData(Data)
    }

    private(set) var operations: [Operation] = []

    var writtenText: String? {
        guard case let .writeText(text) = operations.last else {
            return nil
        }
        return text
    }

    var writtenFileURL: URL? {
        guard case let .writeFileURL(url) = operations.last else {
            return nil
        }
        return url
    }

    func writeText(_ text: String) {
        operations.append(.writeText(text))
    }

    func writeFileURL(_ url: URL) {
        operations.append(.writeFileURL(url))
    }

    func writeImageData(_ data: Data) {
        operations.append(.writeImageData(data))
    }
}

private final class FakePasteEventSender: PasteEventSender {
    private(set) var sendCopyCount = 0
    private(set) var sendPasteCount = 0

    var didSendCopy: Bool {
        sendCopyCount > 0
    }

    var didSendPaste: Bool {
        sendPasteCount > 0
    }

    func sendCopyShortcut() {
        sendCopyCount += 1
    }

    func sendPasteShortcut() {
        sendPasteCount += 1
    }
}

private extension ClipboardItem {
    static func testItem(
        kind: ClipboardContentKind = .text,
        text: String? = nil,
        originalPath: String? = nil,
        cachedFilePath: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: text ?? originalPath ?? cachedFilePath ?? "Unsupported",
            searchableText: text ?? originalPath ?? cachedFilePath ?? "",
            text: text,
            originalPath: originalPath,
            cachedFilePath: cachedFilePath,
            thumbnailPath: nil,
            sourceApp: "Tests",
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: nil,
            useCount: 0,
            isPinned: false,
            isFavorite: false
        )
    }
}

private func temporaryImageURL(data: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteActionServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let fileURL = root.appendingPathComponent("cached-image.png")
    try data.write(to: fileURL)
    return fileURL
}

private func makeTIFFImageData() throws -> Data {
    let image = NSImage(size: NSSize(width: 1, height: 1))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 1, height: 1).fill()
    image.unlockFocus()
    guard let data = image.tiffRepresentation else {
        throw PasteActionError.invalidImageData
    }
    return data
}
