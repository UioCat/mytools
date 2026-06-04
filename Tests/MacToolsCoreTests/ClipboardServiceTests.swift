import XCTest
@testable import MacToolsCore

final class ClipboardServiceTests: XCTestCase {
    func testRecordsNewPayloadWhenRecordingEnabled() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(text: "hello clipboard"),
            changeCount: 0
        )
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: .defaults
        )

        pasteboard.changeCount = 1
        try service.pollOnce(sourceApp: "Tests")

        let results = try repository.search("hello", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].text, "hello clipboard")
        XCTAssertEqual(results[0].sourceApp, "Tests")
    }

    func testDoesNotRecordWhenPaused() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(text: "secret"),
            changeCount: 0
        )
        var settings = AppSettings.defaults
        settings.clipboard.isRecordingEnabled = false
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: settings
        )

        pasteboard.changeCount = 1
        try service.pollOnce(sourceApp: "Tests")

        XCTAssertTrue(try repository.search("", limit: 10).isEmpty)
    }

    func testPausedPollAdvancesLastChangeCount() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(text: "paused payload"),
            changeCount: 0
        )
        var settings = AppSettings.defaults
        settings.clipboard.isRecordingEnabled = false
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: settings
        )

        pasteboard.changeCount = 1
        try service.pollOnce(sourceApp: "Tests")
        settings.clipboard.isRecordingEnabled = true
        service.updateSettings(settings)
        try service.pollOnce(sourceApp: "Tests")

        XCTAssertTrue(try repository.search("", limit: 10).isEmpty)
    }

    func testUnchangedChangeCountDoesNothing() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(text: "initial"),
            changeCount: 0
        )
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            repository: repository,
            settings: .defaults
        )

        try service.pollOnce(sourceApp: "Tests")

        XCTAssertTrue(try repository.search("", limit: 10).isEmpty)
    }
}

private final class FakePasteboardClient: PasteboardClient {
    var payload: ClipboardPayload
    var changeCount: Int

    init(payload: ClipboardPayload, changeCount: Int) {
        self.payload = payload
        self.changeCount = changeCount
    }

    func readPayload() -> ClipboardPayload {
        payload
    }
}
