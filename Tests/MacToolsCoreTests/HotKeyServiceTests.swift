import XCTest
@testable import MacToolsCore

final class HotKeyServiceTests: XCTestCase {
    func testDefaultBindingsProduceToolIDs() {
        let service = HotKeyService(registrar: FakeHotKeyRegistrar())
        service.configure(settings: .defaults) { _ in }

        XCTAssertEqual(service.binding(for: "Option+Space"), .mainPanel)
        XCTAssertEqual(service.binding(for: "Option+1"), .clipboard)
        XCTAssertEqual(service.binding(for: "Option+2"), .translation)
        XCTAssertEqual(service.binding(for: "Option+3"), .screenCapture)
        XCTAssertEqual(service.binding(for: "Control+Command+Left"), .windowLayout(.leftHalf))
        XCTAssertEqual(service.binding(for: "Control+Command+Right"), .windowLayout(.rightHalf))
        XCTAssertEqual(service.binding(for: "Control+Option+Left"), .windowLayout(.leftThird))
        XCTAssertEqual(service.binding(for: "Control+Option+Right"), .windowLayout(.rightThird))
        XCTAssertEqual(service.binding(for: "Option+Command+Left"), .windowLayout(.leftTwoThirds))
        XCTAssertEqual(service.binding(for: "Option+Command+Right"), .windowLayout(.rightTwoThirds))
        XCTAssertEqual(service.binding(for: "Control+Option+0"), .windowLayout(.centered))
        XCTAssertEqual(service.binding(for: "Control+Command+0"), .windowLayout(.maximize))
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

        service.configure(settings: settings) { _ in }

        XCTAssertEqual(service.binding(for: "Option+Command+Left"), .windowLayout(.leftHalf))
        XCTAssertEqual(service.binding(for: "Control+Option+1"), .windowLayout(.leftHalf))
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

        service.configure(settings: settings) { _ in }

        XCTAssertEqual(service.binding(for: "Option+Space"), .mainPanel)
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
