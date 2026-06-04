import Foundation
import XCTest
@testable import MacToolsCore

final class PasteActionServiceTests: XCTestCase {
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
