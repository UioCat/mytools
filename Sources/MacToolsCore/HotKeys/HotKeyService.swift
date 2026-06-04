import Foundation

#if canImport(Carbon)
import Carbon
#endif

public enum HotKeyRegistrationError: Error, Equatable {
    case unsupportedKey(String)
    case unsupportedModifiers([String])
    case registrationFailed(OSStatus)
}

public final class HotKeyService {
    private let registrar: HotKeyRegistrar
    private var bindings: [String: HotKeyTarget] = [:]

    public init(registrar: HotKeyRegistrar) {
        self.registrar = registrar
    }

    public func configure(
        settings: AppSettings,
        handler: @escaping (HotKeyTarget) -> Void = { _ in }
    ) {
        registrar.unregisterAll()
        bindings = [
            settings.mainPanelShortcut.displayValue: .mainPanel,
            settings.clipboardShortcut.displayValue: .clipboard,
            settings.reservedTool2Shortcut.displayValue: .reservedTool2,
            settings.reservedTool3Shortcut.displayValue: .reservedTool3
        ]

        for (hotKey, target) in hotKeys(from: settings) {
            try? registrar.register(hotKey) {
                handler(target)
            }
        }
    }

    public func binding(for displayValue: String) -> HotKeyTarget? {
        bindings[displayValue]
    }

    private func hotKeys(from settings: AppSettings) -> [(HotKey, HotKeyTarget)] {
        [
            (settings.mainPanelShortcut.hotKey, .mainPanel),
            (settings.clipboardShortcut.hotKey, .clipboard),
            (settings.reservedTool2Shortcut.hotKey, .reservedTool2),
            (settings.reservedTool3Shortcut.hotKey, .reservedTool3)
        ]
    }
}

private extension HotKeyBinding {
    var hotKey: HotKey {
        HotKey(displayValue: displayValue, key: key, modifiers: modifiers)
    }
}

#if canImport(Carbon)
public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    private let keyCodes: [String: UInt32] = [
        "Space": 49,
        "1": 18,
        "2": 19,
        "3": 20
    ]
    private let optionModifier = UInt32(optionKey)
    private let signature = OSType.from(string: "MTHK")

    private var eventHandler: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var nextIdentifier: UInt32 = 1

    public init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    public func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {
        guard let keyCode = keyCodes[hotKey.key] else {
            throw HotKeyRegistrationError.unsupportedKey(hotKey.key)
        }
        let modifiers = try carbonModifiers(for: hotKey.modifiers)

        let identifier = nextIdentifier
        nextIdentifier += 1

        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotKeyRegistrationError.registrationFailed(status)
        }

        registrations[identifier] = hotKeyRef
        handlers[identifier] = handler
    }

    public func unregisterAll() {
        for hotKeyRef in registrations.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        registrations.removeAll()
        handlers.removeAll()
    }

    private func carbonModifiers(for modifiers: [String]) throws -> UInt32 {
        guard modifiers == ["Option"] else {
            throw HotKeyRegistrationError.unsupportedModifiers(modifiers)
        }
        return optionModifier
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else {
                    return status
                }

                let registrar = Unmanaged<CarbonHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                registrar.invokeHandler(for: hotKeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandler
        )
    }

    private func invokeHandler(for identifier: UInt32) {
        handlers[identifier]?()
    }
}

private extension OSType {
    static func from(string: String) -> OSType {
        string.utf8.reduce(0) { value, character in
            (value << 8) + OSType(character)
        }
    }
}
#else
public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    public init() {}

    public func register(_ hotKey: HotKey, handler: @escaping () -> Void) throws {}

    public func unregisterAll() {}
}
#endif
