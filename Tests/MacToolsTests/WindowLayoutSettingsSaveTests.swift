import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

@MainActor
final class WindowLayoutSettingsSaveTests: XCTestCase {
    func testLegacyShortcutFailureDoesNotPreventSavingLayoutVisibility() async throws {
        for unsupported in [true, false] {
            let preferences = try makePreferences()
            var previous = AppSettings.defaults
            let registrar = SettingsSaveHotKeyRegistrar()
            if unsupported {
                previous.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])
            } else {
                registrar.failingDisplayValue = "Option+1"
            }
            try preferences.save(previous)
            let service = HotKeyService(registrar: registrar)
            XCTAssertEqual(service.configure(settings: previous).count, 1)
            var draft = previous
            draft.windowLayout.enabledModes.removeAll { $0 == .maximize }

            try AppEnvironment.persistSettings(draft,
                validateHotKeys: {
                    let restore = try service.configureForSave(settings: $0)
                    return { XCTAssertTrue(restore().isEmpty) }
                },
                persist: { try preferences.save($0) }
            )

            XCTAssertEqual(try preferences.load()?.windowLayout, draft.windowLayout)
            XCTAssertEqual(registrar.unregisterAllCallCount, 1)
        }
    }

    func testPreferenceFailureRestoresBindingsAfterPartialStartupRegistration() async throws {
        let registrar = SettingsSaveHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var previous = AppSettings.defaults
        previous.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])
        service.configure(settings: previous)
        let original = registrar.registeredHotKeys
        var draft = previous
        draft.windowLayout = draft.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )

        XCTAssertThrowsError(try AppEnvironment.persistSettings(draft,
            validateHotKeys: {
                let restore = try service.configureForSave(settings: $0)
                return { XCTAssertTrue(restore().isEmpty) }
            },
            persist: { _ in throw SaveError.persistence }
        )) { error in
            XCTAssertEqual(error as? SaveError, .persistence)
        }

        XCTAssertEqual(registrar.registeredHotKeys, original)
    }

    func testPreferenceFailureRestoresChangedOrRemovedLegacyFailureAndOriginalHandler() async throws {
        for replacement in [HotKeyBinding(key: "8", modifiers: ["Option"]), nil] {
            let registrar = SettingsSaveHotKeyRegistrar()
            registrar.failingDisplayValue = "Control+Command+0"
            let service = HotKeyService(registrar: registrar)
            let previous = AppSettings.defaults
            var invoked: [HotKeyTarget] = []
            XCTAssertEqual(service.configure(settings: previous) { invoked.append($0) }.count, 1)
            let original = registrar.registeredHotKeys
            var draft = previous
            draft.windowLayout = draft.windowLayout.replacingPrimaryShortcut(for: .maximize, with: replacement)

            XCTAssertThrowsError(try AppEnvironment.persistSettings(draft,
                validateHotKeys: {
                    let restore = try service.configureForSave(settings: $0) { _ in XCTFail("Unsaved handler invoked") }
                    return { XCTAssertTrue(restore().isEmpty) }
                },
                persist: { _ in throw SaveError.persistence }
            )) { error in
                XCTAssertEqual(error as? SaveError, .persistence)
            }

            XCTAssertEqual(registrar.registeredHotKeys, original)
            XCTAssertNil(registrar.handlers["Option+8"])
            registrar.handlers["Option+2"]?()
            XCTAssertEqual(invoked, [.translation])
            let registrationCount = registrar.unregisterAllCallCount
            XCTAssertTrue(service.configure(settings: previous).isEmpty)
            XCTAssertEqual(registrar.unregisterAllCallCount, registrationCount)
        }
    }

    func testRejectedRegistrationDoesNotPersistNewSettings() async throws {
        let preferences = try makePreferences()
        let previous = AppSettings.defaults
        try preferences.save(previous)
        let originalData = try preferences.rawData()
        var draft = previous
        draft.windowLayout.modeShortcuts = [WindowLayoutModeShortcuts(mode: .maximize, shortcuts: [.init(key: "8", modifiers: ["Option"])])]

        XCTAssertThrowsError(try AppEnvironment.persistSettings(draft,
            validateHotKeys: {
                if $0.windowLayout.modeShortcuts.first?.shortcuts.first?.key == "8" {
                    throw SaveError.registration
                }
                return {}
            },
            persist: { try preferences.save($0) }
        ))
        XCTAssertEqual(try preferences.rawData(), originalData)
    }

    func testPreferenceFailureRestoresPreviousHotKeyRegistration() async throws {
        var draft = AppSettings.defaults
        draft.appearanceMode = .dark
        var validated: [AppSettings] = []
        XCTAssertThrowsError(try AppEnvironment.persistSettings(draft,
            validateHotKeys: {
                validated.append($0)
                return { validated.append(.defaults) }
            },
            persist: { _ in throw SaveError.persistence }
        ))
        XCTAssertEqual(validated, [draft, .defaults])
    }

    private func makePreferences() throws -> PreferenceRepository {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return PreferenceRepository(database: try MacToolsDatabase.at(root.appendingPathComponent("test.sqlite")))
    }
}

private enum SaveError: Error, Equatable { case registration, persistence }

private final class SettingsSaveHotKeyRegistrar: HotKeyRegistrar {
    private(set) var registeredHotKeys: [HotKey] = []
    private(set) var unregisterAllCallCount = 0
    var failingDisplayValue: String?
    private(set) var handlers: [String: () -> Void] = [:]

    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {
        if hotKey.displayValue == failingDisplayValue { throw SaveError.registration }
        registeredHotKeys.append(hotKey)
        handlers[hotKey.displayValue] = handler
    }

    func unregisterAll() {
        unregisterAllCallCount += 1
        registeredHotKeys.removeAll()
        handlers.removeAll()
    }
}
