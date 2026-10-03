import XCTest
@testable import MacToolsCore

final class HotKeyServiceTests: XCTestCase {
    func testRestorationFailureIsRetriedWhenReapplyingOriginalSettings() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        service.configure(settings: .defaults)
        let original = registrar.registeredHotKeys
        var draft = AppSettings.defaults
        draft.windowLayout = draft.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )
        registrar.failuresByRegistrationPass = [2: ["Option+8"], 3: ["Option+1"]]
        XCTAssertEqual(service.configure(settings: draft).map(\.hotKey.displayValue), ["Option+8", "Option+1"])
        XCTAssertNil(registrar.handler(for: "Option+1"))
        registrar.failuresByRegistrationPass = [:]

        XCTAssertTrue(service.configure(settings: .defaults).isEmpty)

        XCTAssertEqual(registrar.registeredHotKeys, original)
        XCTAssertNotNil(registrar.handler(for: "Option+1"))
    }

    func testRestorationFailureDoesNotBecomeToleratedLegacyFailure() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        service.configure(settings: .defaults)
        var draft = AppSettings.defaults
        draft.windowLayout = draft.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )
        registrar.failuresByRegistrationPass = [2: ["Option+8"], 3: ["Option+1"]]
        XCTAssertFalse(service.configure(settings: draft).isEmpty)
        registrar.failuresByRegistrationPass = [:]
        registrar.failingDisplayValue = "Option+1"

        let failures = service.configure(settings: draft)

        XCTAssertTrue(failures.contains { $0.hotKey.displayValue == "Option+1" })
        XCTAssertNil(registrar.handler(for: "Option+8"))
    }

    func testConfigureForSaveRejectsInitialPartialConfigurationWithoutLeavingBindings() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        settings.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])

        XCTAssertThrowsError(try service.configureForSave(settings: settings))

        XCTAssertTrue(registrar.registeredHotKeys.isEmpty)
        XCTAssertTrue(service.configure(settings: .defaults).isEmpty)
    }

    func testSaveRollbackRestoresHandlerAfterUnchangedConfiguration() throws {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var invoked: [HotKeyTarget] = []
        service.configure(settings: .defaults) { invoked.append($0) }

        let restore = try service.configureForSave(settings: .defaults) { _ in XCTFail("Rejected handler invoked") }
        XCTAssertTrue(restore().isEmpty)
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(invoked, [.translation])
    }

    func testLegacyUnsupportedShortcutDoesNotBlockLayoutChanges() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        settings.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])
        XCTAssertEqual(service.configure(settings: settings).count, 1)
        settings.windowLayout = settings.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )
        var invoked: [HotKeyTarget] = []

        XCTAssertTrue(service.configure(settings: settings) { invoked.append($0) }.isEmpty)
        registrar.handler(for: "Option+8")?()
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(invoked, [.windowLayout(.maximize), .translation])
        XCTAssertNil(registrar.handler(for: "Option+F20"))
    }

    func testLegacyOccupiedShortcutDoesNotBlockLayoutChanges() {
        let registrar = FakeHotKeyRegistrar()
        registrar.failingDisplayValue = "Option+1"
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        XCTAssertEqual(service.configure(settings: settings).count, 1)
        settings.windowLayout = settings.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )

        XCTAssertTrue(service.configure(settings: settings).isEmpty)
        XCTAssertNotNil(registrar.handler(for: "Option+8"))
        XCTAssertNil(registrar.handler(for: "Option+1"))
    }

    func testUnchangedPartialConfigurationUpdatesHandlerWithoutReregistering() {
        let registrar = FakeHotKeyRegistrar()
        registrar.failingDisplayValue = "Option+1"
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        XCTAssertEqual(service.configure(settings: settings).count, 1)
        settings.windowLayout.enabledModes.removeAll { $0 == .maximize }
        var invoked: [HotKeyTarget] = []

        XCTAssertTrue(service.configure(settings: settings) { invoked.append($0) }.isEmpty)
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
        XCTAssertEqual(invoked, [.translation])
    }

    func testNewFailureStillRollsBackAfterLegacyFailure() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        settings.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])
        var invoked: [HotKeyTarget] = []
        service.configure(settings: settings) { invoked.append($0) }
        let original = registrar.registeredHotKeys
        settings.windowLayout = settings.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )
        registrar.failingDisplayValue = "Option+8"

        let failures = service.configure(settings: settings) { _ in XCTFail("Rejected handler was installed") }
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(failures.map(\.hotKey.displayValue), ["Option+8"])
        XCTAssertEqual(registrar.registeredHotKeys, original)
        XCTAssertEqual(invoked, [.translation])
    }

    func testUnavailableShortcutReassignedToAnotherTargetMustRegisterSuccessfully() {
        let registrar = FakeHotKeyRegistrar()
        registrar.failingDisplayValue = "Control+Command+0"
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        XCTAssertEqual(service.configure(settings: settings).count, 1)
        let original = registrar.registeredHotKeys
        settings.windowLayout = settings.windowLayout.replacingPrimaryShortcut(for: .maximize, with: nil)
            .replacingPrimaryShortcut(for: .leftHalf, with: HotKeyBinding(key: "0", modifiers: ["Control", "Command"]))

        XCTAssertEqual(service.configure(settings: settings).map(\.hotKey.displayValue), ["Control+Command+0"])
        XCTAssertEqual(registrar.registeredHotKeys, original)
    }

    func testRecoveredLegacyShortcutFailureStillBlocksLaterChanges() {
        let registrar = FakeHotKeyRegistrar()
        registrar.failingDisplayValue = "Option+1"
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        XCTAssertEqual(service.configure(settings: settings).count, 1)
        registrar.failingDisplayValue = nil
        settings.windowLayout = settings.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "8", modifiers: ["Option"])
        )
        XCTAssertTrue(service.configure(settings: settings).isEmpty)
        XCTAssertNotNil(registrar.handler(for: "Option+1"))
        settings.windowLayout = settings.windowLayout.replacingPrimaryShortcut(
            for: .maximize, with: HotKeyBinding(key: "9", modifiers: ["Option"])
        )
        registrar.failingDisplayValue = "Option+1"

        let failures = service.configure(settings: settings)

        XCTAssertTrue(failures.contains { $0.hotKey.displayValue == "Option+1" })
        XCTAssertNotNil(registrar.handler(for: "Option+8"))
        XCTAssertNil(registrar.handler(for: "Option+9"))
    }

    func testUnsupportedLegacyShortcutDoesNotDisableOtherToolsAtStartup() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        settings.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])
        var invoked: [HotKeyTarget] = []

        let failures = service.configure(settings: settings) { invoked.append($0) }
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(failures.map(\.hotKey.displayValue), ["Option+F20"])
        XCTAssertEqual(invoked, [.translation])
        XCTAssertTrue(registrar.registeredHotKeys.contains { $0.displayValue == "Option+Space" })
    }

    func testInvalidReplacementKeepsExistingBindings() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        service.configure(settings: .defaults)
        let original = registrar.registeredHotKeys
        var settings = AppSettings.defaults
        settings.clipboardShortcut = HotKeyBinding(key: "F20", modifiers: ["Option"])

        XCTAssertEqual(service.configure(settings: settings).count, 1)
        XCTAssertEqual(registrar.registeredHotKeys, original)
        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
    }

    func testUnchangedConfigurationUpdatesHandlerWithoutReregistering() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        service.configure(settings: .defaults) { _ in XCTFail("old handler invoked") }
        var invoked: [HotKeyTarget] = []
        service.configure(settings: .defaults) { invoked.append($0) }
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(invoked, [.translation])
        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
    }

    func testFailedReplacementRestoresPreviousRegistrationsAndHandlers() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var invokedTargets: [HotKeyTarget] = []
        service.configure(settings: .defaults) { invokedTargets.append($0) }
        let original = registrar.registeredHotKeys
        var updated = AppSettings.defaults
        updated.clipboardShortcut = HotKeyBinding(key: "C", modifiers: ["Option"])
        registrar.failingDisplayValue = "Option+C"

        let failures = service.configure(settings: updated) { _ in XCTFail("failed configuration must not replace handlers") }
        registrar.handler(for: "Option+1")?()

        XCTAssertEqual(registrar.registeredHotKeys, original)
        XCTAssertEqual(invokedTargets, [.clipboard])
        XCTAssertEqual(failures.map(\.hotKey.displayValue), ["Option+C"])
    }

    func testDefaultRegistrationsInvokeToolAndWindowLayoutTargets() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var invokedTargets: [HotKeyTarget] = []
        service.configure(settings: .defaults) { target in
            invokedTargets.append(target)
        }

        for hotKey in registrar.registeredHotKeys {
            registrar.handler(for: hotKey.displayValue)?()
        }

        XCTAssertEqual(
            invokedTargets,
            [
                .mainPanel,
                .clipboard,
                .translation,
                .screenCapture,
                .windowLayout(.leftHalf),
                .windowLayout(.rightHalf),
                .windowLayout(.topHalf),
                .windowLayout(.bottomHalf),
                .windowLayout(.leftThird),
                .windowLayout(.rightThird),
                .windowLayout(.topThird),
                .windowLayout(.bottomThird),
                .windowLayout(.leftTwoThirds),
                .windowLayout(.rightTwoThirds),
                .windowLayout(.topTwoThirds),
                .windowLayout(.bottomTwoThirds),
                .windowLayout(.centered),
                .windowLayout(.maximize)
            ]
        )
    }

    func testConfigureUnregistersAndRegistersDefaultHotKeys() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)

        service.configure(settings: .defaults) { _ in }

        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
        XCTAssertEqual(
            registrar.registeredHotKeys.map(\.displayValue),
            [
                "Option+Space",
                "Option+1",
                "Option+2",
                "Option+3",
                "Control+Command+Left",
                "Control+Command+Right",
                "Control+Command+Up",
                "Control+Command+Down",
                "Control+Option+Left",
                "Control+Option+Right",
                "Control+Option+Up",
                "Control+Option+Down",
                "Option+Command+Left",
                "Option+Command+Right",
                "Option+Command+Up",
                "Option+Command+Down",
                "Control+Option+0",
                "Control+Command+0"
            ]
        )
    }

    func testConfigureRegistersWindowLayoutHotKeys() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        settings.windowLayout = WindowLayoutSettings(
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .leftHalf,
                    shortcuts: [
                        HotKeyBinding(key: "Left", modifiers: ["Option", "Command"]),
                        HotKeyBinding(key: "1", modifiers: ["Control", "Option"])
                    ]
                )
            ]
        )

        var invokedTargets: [HotKeyTarget] = []
        service.configure(settings: settings) { target in
            invokedTargets.append(target)
        }
        registrar.handler(for: "Option+Command+Left")?()
        registrar.handler(for: "Control+Option+1")?()

        XCTAssertEqual(invokedTargets, [.windowLayout(.leftHalf), .windowLayout(.leftHalf)])
        XCTAssertEqual(
            registrar.registeredHotKeys.map(\.displayValue),
            ["Option+Space", "Option+1", "Option+2", "Option+3", "Option+Command+Left", "Control+Option+1"]
        )
    }

    func testBuiltInToolHotKeysWinWhenWindowLayoutShortcutDuplicatesThem() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var settings = AppSettings.defaults
        settings.windowLayout = WindowLayoutSettings(
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .leftHalf,
                    shortcuts: [HotKeyBinding(key: "Space", modifiers: ["Option"])]
                )
            ]
        )

        var invokedTargets: [HotKeyTarget] = []
        service.configure(settings: settings) { target in
            invokedTargets.append(target)
        }
        registrar.handler(for: "Option+Space")?()

        XCTAssertEqual(invokedTargets, [.mainPanel])
        XCTAssertEqual(
            registrar.registeredHotKeys.map(\.displayValue),
            ["Option+Space", "Option+1", "Option+2", "Option+3"]
        )
    }

    func testRegisteredHandlersInvokeTargets() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var invokedTargets: [HotKeyTarget] = []

        service.configure(settings: .defaults) { target in
            invokedTargets.append(target)
        }
        registrar.handler(for: "Option+Space")?()
        registrar.handler(for: "Option+1")?()
        registrar.handler(for: "Option+2")?()

        XCTAssertEqual(invokedTargets, [.mainPanel, .clipboard, .translation])
    }

    func testWindowLayoutHandlerInvokesModeTarget() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)
        var invokedTargets: [HotKeyTarget] = []
        var settings = AppSettings.defaults
        settings.windowLayout = WindowLayoutSettings(
            modeShortcuts: [
                WindowLayoutModeShortcuts(
                    mode: .rightHalf,
                    shortcuts: [HotKeyBinding(key: "Right", modifiers: ["Option", "Command"])]
                )
            ]
        )

        service.configure(settings: settings) { target in
            invokedTargets.append(target)
        }
        registrar.handler(for: "Option+Command+Right")?()

        XCTAssertEqual(invokedTargets, [.windowLayout(.rightHalf)])
    }
}

private final class FakeHotKeyRegistrar: HotKeyRegistrar {
    private(set) var registeredHotKeys: [HotKey] = []
    private(set) var unregisterAllCallCount = 0
    private var handlers: [String: () -> Void] = [:]
    var failingDisplayValue: String?
    var failuresByRegistrationPass: [Int: Set<String>] = [:]

    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {
        if hotKey.displayValue == failingDisplayValue
            || failuresByRegistrationPass[unregisterAllCallCount]?.contains(hotKey.displayValue) == true {
            throw HotKeyRegistrationError.registrationFailed(-9878)
        }
        registeredHotKeys.append(hotKey)
        handlers[hotKey.displayValue] = handler
    }

    func unregisterAll() {
        unregisterAllCallCount += 1
        registeredHotKeys.removeAll()
        handlers.removeAll()
    }

    func handler(for displayValue: String) -> (() -> Void)? {
        handlers[displayValue]
    }
}
