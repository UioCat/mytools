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
        XCTAssertEqual(settings.clipboard.cacheStoragePath, "")
        XCTAssertEqual(ClipboardCacheLimit.allowedMegabytes, [200, 500, 1024, 2048])
        XCTAssertTrue(settings.superRightClick.isEnabled)
        XCTAssertEqual(settings.superRightClick.longPressMilliseconds, 250)
        XCTAssertEqual(settings.translation.providerID, "bailian")
        XCTAssertEqual(settings.translation.model, "qwen-mt-turbo")
        XCTAssertEqual(settings.translation.endpointURLString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
        XCTAssertEqual(settings.translation.apiKey, "")
        XCTAssertFalse(settings.translation.isConfigured)
        XCTAssertEqual(settings.translation.displayAPIKey(isRevealed: false), "")
        XCTAssertTrue(settings.windowLayout.isEnabled)
        XCTAssertEqual(settings.windowLayout.enabledModes, WindowLayoutMode.allCases)
        XCTAssertEqual(settings.windowLayout.modeShortcuts.map(\.mode), WindowLayoutMode.allCases)
        XCTAssertEqual(
            WindowLayoutMode.allCases.map { settings.windowLayout.shortcuts(for: $0).map(\.displayValue) },
            [
                ["Control+Command+Left"],
                ["Control+Command+Right"],
                ["Control+Option+Left"],
                ["Control+Option+Right"],
                ["Option+Command+Left"],
                ["Option+Command+Right"],
                ["Control+Option+0"],
                ["Control+Command+0"]
            ]
        )
        XCTAssertEqual(settings.windowLayout.visibleButtons.map(\.title), [
            "左半屏",
            "右半屏",
            "左 1/3",
            "右 1/3",
            "左 2/3",
            "右 2/3",
            "居中",
            "满屏"
        ])
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
        settings.clipboard.maxCacheMegabytes = 2048
        settings.clipboard.cacheStoragePath = "/tmp/MacToolsClipboardCache"
        settings.translation.apiKey = "sk-test-key"
        settings.windowLayout.modeShortcuts = [
            WindowLayoutModeShortcuts(
                mode: .leftHalf,
                shortcuts: [
                    HotKeyBinding(key: "Left", modifiers: ["Option", "Command"]),
                    HotKeyBinding(key: "1", modifiers: ["Control", "Option"])
                ]
            )
        ]

        try store.save(settings)
        let loaded = try store.load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(loaded, settings)
        XCTAssertEqual(loaded.mainPanelShortcut.displayValue, "Option+Space")
        XCTAssertEqual(loaded.clipboard.maxCacheMegabytes, 2048)
        XCTAssertEqual(loaded.clipboard.cacheStoragePath, "/tmp/MacToolsClipboardCache")
        XCTAssertEqual(loaded.translation.apiKey, "sk-test-key")
        XCTAssertEqual(loaded.windowLayout.shortcuts(for: .leftHalf).map(\.displayValue), [
            "Option+Command+Left",
            "Control+Option+1"
        ])
    }

    func testClipboardCacheLimitUsesConfiguredStops() {
        XCTAssertEqual(ClipboardCacheLimit.normalizedMegabytes(180), 200)
        XCTAssertEqual(ClipboardCacheLimit.normalizedMegabytes(420), 500)
        XCTAssertEqual(ClipboardCacheLimit.normalizedMegabytes(900), 1024)
        XCTAssertEqual(ClipboardCacheLimit.normalizedMegabytes(1900), 2048)
        XCTAssertEqual(ClipboardCacheLimit.displayValue(for: 1024), "1024 MB")
        XCTAssertEqual(ClipboardCacheLimit.bytes(forMegabytes: 200), 200 * 1024 * 1024)
    }

    func testHotKeyBindingNormalizesDisplayValues() {
        XCTAssertEqual(
            HotKeyBinding(key: "left", modifiers: ["cmd", "option", "option"]).displayValue,
            "Option+Command+Left"
        )
        XCTAssertEqual(
            HotKeyBinding.parse(displayValue: "ctrl + alt + 1")?.displayValue,
            "Control+Option+1"
        )
        XCTAssertNil(HotKeyBinding.parse(displayValue: "1"))
    }

    func testLegacyClipboardSettingsWithoutCacheStoragePathUseDefaultStoragePath() throws {
        let legacyJSON = """
        {
          "isRecordingEnabled": true,
          "maxHistoryCount": 500,
          "maxCacheMegabytes": 1024
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))

        let loaded = try JSONDecoder().decode(ClipboardSettings.self, from: data)

        XCTAssertEqual(loaded.cacheStoragePath, "")
        XCTAssertEqual(loaded.maxCacheMegabytes, 1024)
    }

    func testClipboardSettingsExpandsConfiguredCacheDirectory() {
        let settings = ClipboardSettings(
            isRecordingEnabled: true,
            maxHistoryCount: 500,
            maxCacheMegabytes: 1024,
            cacheStoragePath: "~/MacToolsClipboard"
        )
        let defaultDirectory = URL(fileURLWithPath: "/tmp/default-cache", isDirectory: true)

        XCTAssertEqual(
            settings.cacheDirectory(defaultDirectory: defaultDirectory).path,
            NSString(string: "~/MacToolsClipboard").expandingTildeInPath
        )
        XCTAssertEqual(
            ClipboardSettings(
                isRecordingEnabled: true,
                maxHistoryCount: 500,
                maxCacheMegabytes: 1024
            ).cacheDirectory(defaultDirectory: defaultDirectory),
            defaultDirectory
        )
    }

    func testClipboardCacheStorageDisplayShowsDefaultAndConfiguredDirectories() {
        let defaultDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MacTools/ClipboardCache", isDirectory: true)

        XCTAssertEqual(
            ClipboardCacheStorageDisplay.displayPath(configuredPath: "", defaultDirectory: defaultDirectory),
            "~/Library/Application Support/MacTools/ClipboardCache"
        )
        XCTAssertEqual(
            ClipboardCacheStorageDisplay.displayPath(
                configuredPath: " ~/MacToolsClipboard ",
                defaultDirectory: defaultDirectory
            ),
            "~/MacToolsClipboard"
        )
        XCTAssertEqual(
            ClipboardCacheStorageDisplay.displayPath(
                configuredPath: "/tmp/MacToolsClipboardCache",
                defaultDirectory: defaultDirectory
            ),
            "/tmp/MacToolsClipboardCache"
        )
    }

    func testLegacySuperRightClickDelayIsClampedToSliderRangeWhenLoaded() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var legacySettings = AppSettings.defaults
        legacySettings.superRightClick.longPressMilliseconds = 600
        let data = try JSONEncoder().encode(legacySettings)
        try data.write(to: url)

        let loaded = try SettingsStore(fileURL: url).load()

        XCTAssertEqual(loaded.superRightClick.longPressMilliseconds, 350)
    }

    func testLegacySettingsWithoutWindowLayoutUseDefaultWindowLayoutSettings() throws {
        let legacyJSON = """
        {
          "mainPanelShortcut": { "key": "Space", "modifiers": ["Option"] },
          "clipboardShortcut": { "key": "1", "modifiers": ["Option"] },
          "reservedTool2Shortcut": { "key": "2", "modifiers": ["Option"] },
          "reservedTool3Shortcut": { "key": "3", "modifiers": ["Option"] },
          "clipboard": {
            "isRecordingEnabled": true,
            "maxHistoryCount": 500,
            "maxCacheMegabytes": 1024
          },
          "superRightClick": {
            "isEnabled": true,
            "longPressMilliseconds": 250
          },
          "translation": {
            "providerID": "bailian",
            "apiKey": "",
            "model": "qwen-mt-turbo",
            "endpointURLString": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
          }
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyJSON.data(using: .utf8)?.write(to: url)

        let loaded = try SettingsStore(fileURL: url).load()

        XCTAssertEqual(loaded.windowLayout, .defaults)
    }

    func testLegacyWindowLayoutCustomButtonsAreNotVisibleButtons() {
        let settings = WindowLayoutSettings(
            customButtons: [
                WindowLayoutButton(id: "custom.reading", title: "阅读布局", modes: [.leftTwoThirds, .rightThird])
            ]
        )

        XCTAssertEqual(settings.customButtons.map(\.title), ["阅读布局"])
        XCTAssertEqual(settings.visibleButtons.map(\.title), WindowLayoutMode.allCases.map(\.title))
    }

    func testSuperRightClickResponseSpeedUsesSliderStops() {
        XCTAssertEqual(SuperRightClickResponseSpeed.markerMilliseconds, [250, 300, 350])
        XCTAssertEqual(SuperRightClickResponseSpeed.normalizedMilliseconds(240), 250)
        XCTAssertEqual(SuperRightClickResponseSpeed.normalizedMilliseconds(276), 300)
        XCTAssertEqual(SuperRightClickResponseSpeed.normalizedMilliseconds(600), 350)
        XCTAssertEqual(SuperRightClickResponseSpeed.displayValue(for: 300), "300 毫秒")
    }

    func testSuperRightClickResponseSpeedKeepsContinuousDragValueUntilCommit() {
        XCTAssertEqual(SuperRightClickResponseSpeed.clampedSliderValue(240), 250)
        XCTAssertEqual(SuperRightClickResponseSpeed.clampedSliderValue(276.5), 276.5)
        XCTAssertEqual(SuperRightClickResponseSpeed.clampedSliderValue(360), 350)
        XCTAssertEqual(SuperRightClickResponseSpeed.committedMilliseconds(forSliderValue: 276.5), 300)
    }

    func testTranslationAPIKeyDisplayMasksConfiguredSecretUntilRevealed() {
        var settings = AppSettings.defaults
        settings.translation.apiKey = "sk-1234567890"

        XCTAssertEqual(settings.translation.displayAPIKey(isRevealed: false), "*************")
        XCTAssertEqual(settings.translation.displayAPIKey(isRevealed: true), "sk-1234567890")
        XCTAssertTrue(settings.translation.isConfigured)
    }

    func testTranslationAPIKeyInputUsesSecureFieldUntilRevealed() {
        XCTAssertTrue(TranslationAPIKeyInputMode(isRevealed: false).usesSecureField)
        XCTAssertFalse(TranslationAPIKeyInputMode(isRevealed: true).usesSecureField)
    }

    func testTranslationAPIKeyKeyboardCommandRecognizesCopyAndPaste() {
        XCTAssertEqual(
            TranslationAPIKeyKeyboardCommand.command(forKeyCode: 8, isCommandPressed: true),
            .copy
        )
        XCTAssertEqual(
            TranslationAPIKeyKeyboardCommand.command(forKeyCode: 9, isCommandPressed: true),
            .paste
        )
        XCTAssertNil(TranslationAPIKeyKeyboardCommand.command(forKeyCode: 8, isCommandPressed: false))
    }

    func testTranslationAPIKeyKeyboardCommandRecognizesCharactersWhenKeyCodeDiffers() {
        XCTAssertEqual(
            TranslationAPIKeyKeyboardCommand.command(
                forKeyCode: 0,
                charactersIgnoringModifiers: "c",
                isCommandPressed: true
            ),
            .copy
        )
        XCTAssertEqual(
            TranslationAPIKeyKeyboardCommand.command(
                forKeyCode: 0,
                charactersIgnoringModifiers: "V",
                isCommandPressed: true
            ),
            .paste
        )
        XCTAssertNil(
            TranslationAPIKeyKeyboardCommand.command(
                forKeyCode: 0,
                charactersIgnoringModifiers: "v",
                isCommandPressed: false
            )
        )
    }

    func testTranslationAPIKeyKeyboardCommandCopiesWholeFocusedSecret() {
        XCTAssertEqual(
            TranslationAPIKeyKeyboardCommand.copyableString(from: "  sk-test-key\n"),
            "sk-test-key"
        )
        XCTAssertNil(TranslationAPIKeyKeyboardCommand.copyableString(from: " \n "))
    }

    func testTranslationAPIKeyKeyboardCommandPastesTrimmedSecret() {
        XCTAssertEqual(
            TranslationAPIKeyKeyboardCommand.pastedAPIKey(from: "\nsk-pasted-key  "),
            "sk-pasted-key"
        )
        XCTAssertNil(TranslationAPIKeyKeyboardCommand.pastedAPIKey(from: nil))
        XCTAssertNil(TranslationAPIKeyKeyboardCommand.pastedAPIKey(from: "   "))
    }

    func testSettingsFileIsSavedWithOwnerOnlyPermissions() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        let store = SettingsStore(fileURL: url)
        var settings = AppSettings.defaults
        settings.translation.apiKey = "sk-test-key"

        try store.save(settings)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }
}
