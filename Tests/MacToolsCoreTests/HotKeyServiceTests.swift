import XCTest
@testable import MacToolsCore

final class HotKeyServiceTests: XCTestCase {
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

    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {
        if hotKey.displayValue == failingDisplayValue {
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
