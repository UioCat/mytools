import XCTest
@testable import MacToolsCore

final class HotKeyServiceTests: XCTestCase {
    func testDefaultBindingsProduceToolIDs() {
        let service = HotKeyService(registrar: FakeHotKeyRegistrar())
        service.configure(settings: .defaults) { _ in }

        XCTAssertEqual(service.binding(for: "Option+Space"), .mainPanel)
        XCTAssertEqual(service.binding(for: "Option+1"), .clipboard)
        XCTAssertEqual(service.binding(for: "Option+2"), .reservedTool2)
        XCTAssertEqual(service.binding(for: "Option+3"), .reservedTool3)
    }

    func testConfigureUnregistersAndRegistersDefaultHotKeys() {
        let registrar = FakeHotKeyRegistrar()
        let service = HotKeyService(registrar: registrar)

        service.configure(settings: .defaults) { _ in }

        XCTAssertEqual(registrar.unregisterAllCallCount, 1)
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

        XCTAssertEqual(invokedTargets, [.mainPanel, .clipboard])
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
