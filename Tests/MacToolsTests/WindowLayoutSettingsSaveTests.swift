import Foundation
import MacToolsCore
import XCTest
@testable import MacTools

@MainActor
final class WindowLayoutSettingsSaveTests: XCTestCase {
    func testRejectedRegistrationDoesNotPersistNewSettings() async throws {
        let preferences = try makePreferences()
        let previous = AppSettings.defaults
        try preferences.save(previous)
        let originalData = try preferences.rawData()
        var draft = previous
        draft.windowLayout.modeShortcuts = [WindowLayoutModeShortcuts(mode: .maximize, shortcuts: [.init(key: "8", modifiers: ["Option"])])]

        XCTAssertThrowsError(try AppEnvironment.persistSettings(draft, restoring: previous,
            validateHotKeys: {
                if $0.windowLayout.modeShortcuts.first?.shortcuts.first?.key == "8" {
                    throw SaveError.registration
                }
            },
            persist: { try preferences.save($0) }
        ))
        XCTAssertEqual(try preferences.rawData(), originalData)
    }

    func testPreferenceFailureRestoresPreviousHotKeyRegistration() async throws {
        var draft = AppSettings.defaults
        draft.appearanceMode = .dark
        var validated: [AppSettings] = []
        XCTAssertThrowsError(try AppEnvironment.persistSettings(draft, restoring: .defaults,
            validateHotKeys: { validated.append($0) },
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

private enum SaveError: Error { case registration, persistence }
