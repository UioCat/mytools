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
        bindings.removeAll()

        for (hotKey, target) in uniqueHotKeys(from: settings) {
            bindings[hotKey.displayValue] = target
            try? registrar.register(hotKey) {
                handler(target)
            }
        }
    }

    public func binding(for displayValue: String) -> HotKeyTarget? {
        bindings[displayValue]
    }

    private func hotKeys(from settings: AppSettings) -> [(HotKey, HotKeyTarget)] {
        let toolHotKeys: [(HotKey, HotKeyTarget)] = [
            (settings.mainPanelShortcut.hotKey, .mainPanel),
            (settings.clipboardShortcut.hotKey, .clipboard),
            (settings.reservedTool2Shortcut.hotKey, .translation),
            (settings.reservedTool3Shortcut.hotKey, .screenCapture)
        ]

        let windowLayoutHotKeys = settings.windowLayout.shortcutBindings.map { shortcutBinding in
            (shortcutBinding.binding.hotKey, HotKeyTarget.windowLayout(shortcutBinding.mode))
        }

        return toolHotKeys + windowLayoutHotKeys
    }

    private func uniqueHotKeys(from settings: AppSettings) -> [(HotKey, HotKeyTarget)] {
        var seen = Set<String>()
        return hotKeys(from: settings).filter { hotKey, _ in
            hotKey.key.isEmpty == false
                && hotKey.modifiers.isEmpty == false
                && seen.insert(hotKey.displayValue).inserted
        }
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
        "A": 0,
        "S": 1,
        "D": 2,
        "F": 3,
        "H": 4,
        "G": 5,
        "Z": 6,
        "X": 7,
        "C": 8,
        "V": 9,
        "B": 11,
        "Q": 12,
        "W": 13,
        "E": 14,
        "R": 15,
        "Y": 16,
        "T": 17,
        "1": 18,
        "2": 19,
        "3": 20,
        "4": 21,
        "6": 22,
        "5": 23,
        "7": 26,
        "8": 28,
        "9": 25,
        "0": 29,
        "O": 31,
        "U": 32,
        "I": 34,
        "P": 35,
        "Return": 36,
        "L": 37,
        "J": 38,
        "K": 40,
        "N": 45,
        "M": 46,
        "Tab": 48,
        "Space": 49,
        "Delete": 51,
        "Escape": 53,
        "F5": 96,
        "F6": 97,
        "F7": 98,
        "F3": 99,
        "F8": 100,
        "F9": 101,
        "F11": 103,
        "F10": 109,
        "F12": 111,
        "F4": 118,
        "F2": 120,
        "F1": 122,
        "Left": 123,
        "Right": 124,
        "Down": 125,
        "Up": 126
    ]
    private let modifierValues: [String: UInt32] = [
        "Control": UInt32(controlKey),
        "Option": UInt32(optionKey),
        "Shift": UInt32(shiftKey),
        "Command": UInt32(cmdKey)
    ]
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
        guard !modifiers.isEmpty else {
            throw HotKeyRegistrationError.unsupportedModifiers(modifiers)
        }

        var carbonModifiers: UInt32 = 0
        for modifier in modifiers {
            guard let modifierValue = modifierValues[modifier] else {
                throw HotKeyRegistrationError.unsupportedModifiers(modifiers)
            }
            carbonModifiers |= modifierValue
        }
        return carbonModifiers
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
