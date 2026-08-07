import XCTest
@testable import MacToolsCore

final class HotKeyServiceTests: XCTestCase {
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
                .windowLayout(.leftTwoThirds),
                .windowLayout(.rightTwoThirds),
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
                "Option+Command+Left",
                "Option+Command+Right",
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

    func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {
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
