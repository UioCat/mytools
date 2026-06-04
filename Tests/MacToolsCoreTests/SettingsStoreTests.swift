import XCTest
@testable import MacToolsCore

final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchApprovedSettings() {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.mainPanelShortcut.displayValue, "Option+Space")
        XCTAssertEqual(settings.clipboardShortcut.displayValue, "Option+1")
        XCTAssertEqual(settings.reservedTool2Shortcut.displayValue, "Option+2")
        XCTAssertEqual(settings.reservedTool3Shortcut.displayValue, "Option+3")
        XCTAssertTrue(settings.clipboard.isRecordingEnabled)
        XCTAssertEqual(settings.clipboard.maxHistoryCount, 500)
        XCTAssertEqual(settings.clipboard.maxCacheMegabytes, 1024)
        XCTAssertTrue(settings.superRightClick.isEnabled)
        XCTAssertEqual(settings.superRightClick.longPressMilliseconds, 600)
        XCTAssertEqual(settings.translation.providerID, "baidu")
    }

    func testLoadReturnsDefaultsWhenFileDoesNotExist() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)

        let loaded = try store.load()

        XCTAssertEqual(loaded, .defaults)
    }

    func testSettingsRoundTripToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested")
            .appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)
        var settings = AppSettings.defaults
        settings.clipboard.maxHistoryCount = 250

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.mainPanelShortcut.displayValue, "Option+Space")
    }
}
