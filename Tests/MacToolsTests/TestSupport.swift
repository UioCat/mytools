import Foundation
@testable import MacToolsCore

enum MacToolsTestError: Error {
    case expectedFailure
    case unexpectedCall
}

final class FakeWritablePasteboard: WritablePasteboard {
    enum Operation: Equatable {
        case writeText(String)
        case writeFileURL(URL)
        case writeImageData(Data)
    }

    var writeError: Error?
    private(set) var operations: [Operation] = []

    func writeText(_ text: String) {
        operations.append(.writeText(text))
    }

    func writeFileURL(_ url: URL) {
        operations.append(.writeFileURL(url))
    }

    func writeImageData(_ data: Data) throws {
        if let writeError { throw writeError }
        operations.append(.writeImageData(data))
    }
}

final class FakePasteEventSender: PasteEventSender {
    private(set) var sendPasteCount = 0
    func sendCopyShortcut() {}
    func sendPasteShortcut() { sendPasteCount += 1 }
}

@MainActor
final class EventRecorder {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

func makeTestLogger() -> Logger {
    Logger(
        debugLogDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MacToolsTests-\(UUID().uuidString)",
                isDirectory: true
            )
    )
}

extension ClipboardItem {
    static func testItem(
        kind: ClipboardContentKind = .text,
        text: String? = "item",
        originalPath: String? = nil,
        cachedFilePath: String? = nil,
        isFavorite: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            displayTitle: text ?? originalPath ?? cachedFilePath ?? "item",
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
            isFavorite: isFavorite
        )
    }
}
