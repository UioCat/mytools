import AppKit
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

    func testCachesImageDataBeforeRecording() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let imageData = Data([1, 2, 3])
        let cachedPath = "/tmp/cached-image.png"
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(imageData: imageData),
            changeCount: 0
        )
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            settings: .defaults,
            upsert: { item in
                try repository.upsert(item)
            },
            cacheImageData: { data, _ in
                XCTAssertEqual(data, imageData)
                return cachedPath
            }
        )

        pasteboard.changeCount = 1
        try service.pollOnce(sourceApp: "Tests")

        let results = try repository.search("image", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].kind, .imageData)
        XCTAssertEqual(results[0].cachedFilePath, cachedPath)
    }

    func testImageCacheReceivesUpdatedSettingsWhenPolling() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let imageData = Data([4, 5, 6])
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(imageData: imageData),
            changeCount: 0
        )
        var initialSettings = AppSettings.defaults
        initialSettings.clipboard.cacheStoragePath = "/tmp/initial-cache"
        var capturedCachePaths: [String] = []
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            settings: initialSettings,
            upsert: { item in
                try repository.upsert(item)
            },
            cacheImageData: { data, settings in
                XCTAssertEqual(data, imageData)
                capturedCachePaths.append(settings.clipboard.cacheStoragePath)
                return "/tmp/updated-cache/image.png"
            }
        )
        var updatedSettings = initialSettings
        updatedSettings.clipboard.cacheStoragePath = "/tmp/updated-cache"

        service.updateSettings(updatedSettings)
        pasteboard.changeCount = 1
        try service.pollOnce(sourceApp: "Tests")

        XCTAssertEqual(capturedCachePaths, ["/tmp/updated-cache"])
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

    func testRetriesSameChangeAfterFailedPersistence() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(text: "retry me"),
            changeCount: 0
        )
        var upsertAttempts = 0
        let service = ClipboardService(
            pasteboard: pasteboard,
            classifier: ClipboardClassifier(),
            settings: .defaults,
            upsert: { item in
                upsertAttempts += 1
                if upsertAttempts == 1 {
                    throw TestPersistenceError.writeFailed
                }
                try repository.upsert(item)
            }
        )

        pasteboard.changeCount = 1
        XCTAssertThrowsError(try service.pollOnce(sourceApp: "Tests"))
        XCTAssertTrue(try repository.search("", limit: 10).isEmpty)

        try service.pollOnce(sourceApp: "Tests")

        let results = try repository.search("retry", limit: 10)
        XCTAssertEqual(upsertAttempts, 2)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].text, "retry me")
    }

    func testUnknownPayloadAdvancesLastChangeCount() throws {
        let database = try ClipboardDatabase.inMemory()
        let repository = ClipboardRepository(database: database)
        let pasteboard = FakePasteboardClient(
            payload: ClipboardPayload(),
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
        pasteboard.payload = ClipboardPayload(text: "same change count")
        try service.pollOnce(sourceApp: "Tests")

        XCTAssertTrue(try repository.search("", limit: 10).isEmpty)
    }
}

final class PasteboardClientTests: XCTestCase {
    func testFileURLsFromObjectsFiltersOutWebURLs() {
        let fileURL = URL(fileURLWithPath: "/tmp/document.txt")
        let webURL = URL(string: "https://example.com/document.txt")!

        let fileURLs = SystemPasteboardClient.fileURLs(from: [webURL as NSURL, fileURL as NSURL])

        XCTAssertEqual(fileURLs, [fileURL])
    }

    func testReadPayloadConvertsTIFFImageDataToPNG() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(try makeTIFFImageData(), forType: .tiff))

        let payload = SystemPasteboardClient(pasteboard: pasteboard).readPayload()

        XCTAssertEqual(payload.imageData?.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
}

private enum TestPersistenceError: Error {
    case writeFailed
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

private func makeTIFFImageData() throws -> Data {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()

    guard let data = image.tiffRepresentation else {
        throw TestImageError.tiffEncodingFailed
    }
    return data
}

private enum TestImageError: Error {
    case tiffEncodingFailed
}
